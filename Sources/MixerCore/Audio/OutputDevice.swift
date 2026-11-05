import CoreAudio
import Foundation

/// A saída de áudio padrão.
public struct OutputDevice: Equatable, Sendable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let transport: Transport

    public enum Transport: Equatable, Sendable {
        case builtIn, bluetooth, usb, hdmi, other
    }

    public init(id: UInt32, uid: String, name: String, transport: Transport) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }

    public static func current() throws -> OutputDevice {
        let device = try getProperty(systemObject, kAudioHardwarePropertyDefaultOutputDevice,
                                     as: AudioDeviceID.self, default: 0)
        guard device != kAudioObjectUnknown, let uid = getString(device, kAudioDevicePropertyDeviceUID) else {
            throw AudioError("nenhuma saída de áudio padrão")
        }
        let name = getString(device, kAudioObjectPropertyName) ?? "Saída de áudio"
        let transport = (try? getProperty(device, kAudioDevicePropertyTransportType, as: UInt32.self, default: 0)) ?? 0
        return OutputDevice(id: device, uid: uid, name: name, transport: Transport(rawTransport: transport))
    }

    public func nominalSampleRate() -> Double {
        (try? getProperty(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self, default: 0)) ?? 0
    }
}

extension OutputDevice.Transport {
    init(rawTransport value: UInt32) {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .hdmi
        default: self = .other
        }
    }
}
