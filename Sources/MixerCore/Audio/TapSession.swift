import CoreAudio
import Foundation
import os

/// Fase da sessão.
/// - `probing`: tap com `.unmuted`; o IOProc só mede o pico e não escreve na saída. O app original segue
///   tocando normal. Serve pra descobrir se a permissão existe sem arriscar silenciar o app.
/// - `active`: tap com `.mutedWhenTapped`; o IOProc reescreve o áudio com o ganho aplicado.
public enum SessionMode: Equatable, Sendable {
    case probing
    case active
}

/// O que o `SessionManager` precisa de uma sessão. Existe pra poder trocar por uma falsa nos testes.
public protocol AudioSession: AnyObject {
    var gain: GainControl { get }
    func stop()
}

/// Uma sessão de áudio de um app: tap nos processos dele, aggregate device privado com a saída
/// e um IOProc que mede (`probing`) ou reescreve (`active`) o áudio.
public final class TapSession: AudioSession {
    public let processObjects: [UInt32]
    public let outputUID: String
    public let mode: SessionMode
    public let gain: GainControl

    private var resources: Resources
    private static let log = Logger(subsystem: "com.glarruda.mixer", category: "tap")

    /// IDs do Core Audio que precisam ser desfeitos, na ordem inversa da criação.
    private struct Resources {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        var isRunning = false

        mutating func teardown() {
            if isRunning { AudioDeviceStop(aggregateID, procID); isRunning = false }
            if let procID, aggregateID != kAudioObjectUnknown {
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                self.procID = nil
            }
            if aggregateID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateID)
                aggregateID = AudioObjectID(kAudioObjectUnknown)
            }
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }
    }

    public init(processObjects: [UInt32], outputUID: String, fallbackSampleRate: Double,
                initialGain: Float, mode: SessionMode) throws {
        self.processObjects = processObjects
        self.outputUID = outputUID
        self.mode = mode
        (resources, gain) = try Self.build(processObjects: processObjects, outputUID: outputUID,
                                           fallbackSampleRate: fallbackSampleRate, initialGain: initialGain, mode: mode)
    }

    deinit { resources.teardown() }

    public func stop() { resources.teardown() }

    // MARK: - Montagem

    private static func build(processObjects: [UInt32], outputUID: String, fallbackSampleRate: Double,
                              initialGain: Float, mode: SessionMode) throws -> (Resources, GainControl) {
        var resources = Resources()
        do {
            let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
            description.uuid = UUID()
            // `muteBehavior` é definido antes de criar o tap; pra trocar de fase, a sessão é recriada.
            description.muteBehavior = mode == .active ? .mutedWhenTapped : .unmuted
            var created = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(description, &created), "criação do tap")
            resources.tapID = created

            let format = try? getProperty(created, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self,
                                          default: AudioStreamBasicDescription())
            let rate = format.map(\.mSampleRate).flatMap { $0 > 0 ? $0 : nil } ?? fallbackSampleRate
            let tapChannels = format.map { Int($0.mChannelsPerFrame) }.flatMap { $0 > 0 ? $0 : nil } ?? 2

            resources.aggregateID = try createAggregate(outputUID: outputUID, tapUUID: description.uuid)

            let layout = try inputChannelLayout(of: resources.aggregateID)
            let inputIndex = try BufferSelection.tapInputIndex(inputChannels: layout, tapChannels: tapChannels)
            log.info("layout de entrada \(layout, privacy: .public), tap com \(tapChannels) canais no buffer \(inputIndex), modo \(String(describing: mode), privacy: .public)")

            let gain = GainControl(sampleRate: rate > 0 ? rate : 48_000, initialGain: initialGain, inputIndex: inputIndex)
            try startIO(aggregateID: resources.aggregateID, gain: gain, probing: mode == .probing, resources: &resources)
            return (resources, gain)
        } catch {
            resources.teardown()
            throw error
        }
    }

    private static func createAggregate(outputUID: String, tapUUID: UUID) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        var created = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &created), "criação do aggregate device")
        return created
    }

    /// Canais de cada buffer de entrada do aggregate, na ordem em que chegam ao IOProc.
    private static func inputChannelLayout(of device: AudioObjectID) throws -> [Int] {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "layout de entrada")
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw), "layout de entrada")
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    private static func startIO(aggregateID: AudioObjectID, gain: GainControl, probing: Bool,
                                resources: inout Resources) throws {
        let queue = DispatchQueue(label: "mixer.tap-session", qos: .userInteractive)
        var created: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&created, aggregateID, queue) { _, input, _, output, _ in
            if probing {
                gain.processProbe(input: input)
            } else {
                gain.process(input: input, output: output)
            }
        }, "criação do IOProc")
        resources.procID = created
        try check(AudioDeviceStart(aggregateID, created), "início do áudio")
        resources.isRunning = true
    }
}
