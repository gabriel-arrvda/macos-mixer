import CoreAudio
import Foundation

/// Um dispositivo de saída de áudio.
public struct OutputDevice: Equatable, Hashable, Sendable, Identifiable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let transport: Transport

    public enum Transport: Equatable, Hashable, Sendable {
        case builtIn, bluetooth, usb, hdmi, airPlay, other
    }

    public init(id: UInt32, uid: String, name: String, transport: Transport) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }

    /// A saída padrão de agora.
    public static func current() throws -> OutputDevice {
        let device = try getProperty(systemObject, kAudioHardwarePropertyDefaultOutputDevice,
                                     as: AudioDeviceID.self, default: 0)
        guard device != kAudioObjectUnknown, let found = make(device) else {
            throw AudioError("nenhuma saída de áudio padrão")
        }
        return found
    }

    /// Todas as saídas que podem ser escolhidas, na ordem do sistema. Ficam de fora os aggregate devices
    /// (inclusive os privados que o próprio Mixer cria pra cada app) e o que não pode ser saída padrão.
    public static func all() -> [OutputDevice] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id), canBeDefault(id) else { return nil }
            let transport = (try? getProperty(id, kAudioDevicePropertyTransportType, as: UInt32.self, default: 0)) ?? 0
            guard transport != kAudioDeviceTransportTypeAggregate else { return nil }
            return make(id)
        }
    }

    public static func device(uid: String) -> OutputDevice? {
        all().first { $0.uid == uid }
    }

    /// Troca a saída padrão do sistema.
    public static func setDefault(_ device: OutputDevice) throws {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        try check(AudioObjectSetPropertyData(systemObject, &address, 0, nil,
                                             UInt32(MemoryLayout<AudioDeviceID>.size), &id), "troca da saída padrão")
    }

    public func nominalSampleRate() -> Double {
        (try? getProperty(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self, default: 0)) ?? 0
    }

    private static func make(_ device: AudioDeviceID) -> OutputDevice? {
        guard let uid = getString(device, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = getString(device, kAudioObjectPropertyName) ?? "Saída de áudio"
        let transport = (try? getProperty(device, kAudioDevicePropertyTransportType, as: UInt32.self, default: 0)) ?? 0
        return OutputDevice(id: device, uid: uid, name: name, transport: Transport(rawTransport: transport))
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func canBeDefault(_ device: AudioDeviceID) -> Bool {
        let value = try? getProperty(device, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                     scope: kAudioObjectPropertyScopeOutput, as: UInt32.self, default: 1)
        return (value ?? 1) != 0
    }
}

extension OutputDevice.Transport {
    init(rawTransport value: UInt32) {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .hdmi
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        default: self = .other
        }
    }
}
