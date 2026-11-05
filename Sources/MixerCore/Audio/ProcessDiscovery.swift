import CoreAudio
import Foundation

/// Lê do Core Audio a lista de processos que usam áudio.
public enum ProcessDiscovery {
    public static func snapshot() throws -> [AudioProcessInfo] {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size), "lista de processos")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids), "lista de processos")

        return ids.compactMap { object in
            // Um processo pode sumir entre a lista e a leitura: nesse caso só ignora.
            guard let pid = try? getProperty(object, kAudioProcessPropertyPID, as: pid_t.self, default: 0),
                  let running = try? getProperty(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self, default: 0)
            else { return nil }
            return AudioProcessInfo(objectID: object, pid: pid,
                                    bundleID: getString(object, kAudioProcessPropertyBundleID),
                                    isRunningOutput: running != 0)
        }
    }
}
