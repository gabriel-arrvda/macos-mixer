import CoreAudio
import Foundation

/// Uma sessão de áudio de um app: tap nos processos dele (que silencia o original), aggregate device
/// privado com a saída e um IOProc que reescreve o áudio com o ganho aplicado.
public final class TapSession {
    public let processObjects: [UInt32]
    public let outputUID: String
    public let gain: GainControl

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var isRunning = false
    private let queue = DispatchQueue(label: "mixer.tap-session", qos: .userInteractive)

    public init(processObjects: [UInt32], outputUID: String, fallbackSampleRate: Double, initialGain: Float) throws {
        self.processObjects = processObjects
        self.outputUID = outputUID

        let tap = CATapDescription(stereoMixdownOfProcesses: processObjects)
        tap.uuid = UUID()
        tap.muteBehavior = .mutedWhenTapped
        var createdTap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(tap, &createdTap), "criação do tap")
        tapID = createdTap

        let rate = TapSession.sampleRate(of: createdTap) ?? fallbackSampleRate
        gain = GainControl(sampleRate: rate > 0 ? rate : 48_000, initialGain: initialGain)

        do {
            try createAggregate(tapUUID: tap.uuid)
            try startIO()
        } catch {
            teardown()
            throw error
        }
    }

    deinit { teardown() }

    public func stop() { teardown() }

    // MARK: - Montagem

    private func createAggregate(tapUUID: UUID) throws {
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
        aggregateID = created
    }

    private func startIO() throws {
        let gain = self.gain
        var created: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&created, aggregateID, queue) { _, input, _, output, _ in
            gain.process(input: input, output: output)
        }, "criação do IOProc")
        procID = created
        try check(AudioDeviceStart(aggregateID, created), "início do áudio")
        isRunning = true
    }

    private func teardown() {
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

    private static func sampleRate(of tap: AudioObjectID) -> Double? {
        let format = try? getProperty(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self,
                                      default: AudioStreamBasicDescription())
        return format.map { $0.mSampleRate }.flatMap { $0 > 0 ? $0 : nil }
    }
}
