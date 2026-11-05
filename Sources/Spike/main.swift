import CoreAudio
import AudioToolbox
import Foundation

// Spike: captura o áudio de processos específicos (process tap), aplica um ganho fixo
// e reescreve na saída padrão. Uso:
//   Spike --list
//   Spike <ganho 0...1> <pid> [pid...]

struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw SpikeError("\(what) falhou (OSStatus \(status))") }
}

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func getProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type, default value: T) throws -> T {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    var result = value
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result), "leitura da propriedade")
    return result
}

func processObjects() throws -> [AudioObjectID] {
    var addr = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size), "lista de processos")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids), "lista de processos")
    return ids
}

func bundleID(of object: AudioObjectID) -> String {
    var addr = address(kAudioProcessPropertyBundleID)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString? = nil
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return "?" }
    return value as String
}

func translate(pid: pid_t) throws -> AudioObjectID {
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pidValue = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                         UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &object), "tradução de PID")
    guard object != kAudioObjectUnknown else { throw SpikeError("PID \(pid) não é um processo de áudio") }
    return object
}

func defaultOutputUID() throws -> String {
    let device = try getProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                                 as: AudioDeviceID.self, default: 0)
    var addr = address(kAudioDevicePropertyDeviceUID)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var uid: CFString? = nil
    try check(AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid), "UID da saída")
    guard let uid else { throw SpikeError("saída sem UID") }
    return uid as String
}

func listProcesses() throws {
    for object in try processObjects() {
        let pid = try getProperty(object, kAudioProcessPropertyPID, as: pid_t.self, default: 0)
        let running = try getProperty(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self, default: 0)
        print("pid=\(pid)\tsaindo=\(running)\t\(bundleID(of: object))")
    }
}

func run(gain: Float, pids: [pid_t]) throws {
    let objects = try pids.map(translate)
    let outputUID = try defaultOutputUID()

    let tap = CATapDescription(stereoMixdownOfProcesses: objects)
    tap.uuid = UUID()
    tap.muteBehavior = .mutedWhenTapped
    var tapID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateProcessTap(tap, &tapID), "AudioHardwareCreateProcessTap")

    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Mixer Spike",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: tap.uuid.uuidString,
        ]],
    ]
    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "AudioHardwareCreateAggregateDevice")

    var peak: Float = 0 // só pra diagnóstico: mostra se o áudio chega zerado
    var procID: AudioDeviceIOProcID?
    let queue = DispatchQueue(label: "spike.io", qos: .userInteractive)
    try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outBuffers = UnsafeMutableAudioBufferListPointer(output)
        for index in 0..<min(inBuffers.count, outBuffers.count) {
            guard let src = inBuffers[index].mData, let dst = outBuffers[index].mData else { continue }
            let bytes = min(inBuffers[index].mDataByteSize, outBuffers[index].mDataByteSize)
            let count = Int(bytes) / MemoryLayout<Float>.size
            let s = src.assumingMemoryBound(to: Float.self)
            let d = dst.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                d[i] = s[i] * gain
                peak = max(peak, abs(s[i]))
            }
        }
    }, "criação do IOProc")
    try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")

    print("Rodando com ganho \(gain). Ctrl+C para sair.")
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        AudioDeviceStop(aggregateID, procID)
        if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
        exit(0)
    }
    source.resume()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { print(String(format: "pico de entrada: %.4f", peak)); peak = 0 }
    timer.resume()
    dispatchMain()
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--list" {
        try listProcesses()
    } else if args.count >= 2, let gain = Float(args[0]) {
        let pids = args.dropFirst().compactMap { pid_t($0) }
        guard !pids.isEmpty else { throw SpikeError("informe ao menos um PID") }
        try run(gain: min(max(gain, 0), 1), pids: pids)
    } else {
        print("Uso: Spike --list | Spike <ganho 0...1> <pid> [pid...]")
        exit(64)
    }
} catch {
    FileHandle.standardError.write(Data("Erro: \(error)\n".utf8))
    exit(1)
}
