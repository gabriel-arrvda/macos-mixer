import AudioToolbox
import CoreAudio
import Foundation

/// Volume e mudo de um dispositivo. `nil` = o dispositivo não oferece esse controle.
public struct DeviceVolume: Equatable, Sendable {
    public var name: String?
    public var volume: Float?
    public var isMuted: Bool?

    public init(name: String? = nil, volume: Float? = nil, isMuted: Bool? = nil) {
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
    }

    public static let unavailable = DeviceVolume()
}

/// Volume geral da saída padrão e do microfone padrão, pelos controles do próprio dispositivo
/// (o mesmo que o teclado e os Ajustes do Sistema mexem). Não captura áudio do microfone.
public enum SystemAudio {
    public enum Direction { case output, input }

    public static func read(_ direction: Direction) -> DeviceVolume {
        guard let device = defaultDevice(direction) else { return .unavailable }
        let scope = scope(direction)
        return DeviceVolume(name: getString(device, kAudioObjectPropertyName),
                            volume: volume(device, scope: scope),
                            isMuted: muted(device, scope: scope))
    }

    public static func setVolume(_ value: Float, _ direction: Direction) {
        guard let device = defaultDevice(direction) else { return }
        let clamped = min(max(value.isNaN ? 0 : value, 0), 1)
        let scope = scope(direction)
        var main = mainVolumeAddress(scope)
        if AudioHardwareServiceHasProperty(device, &main) {
            var data = Float32(clamped)
            if AudioHardwareServiceSetPropertyData(device, &main, 0, nil, UInt32(MemoryLayout<Float32>.size), &data) == noErr {
                return
            }
        }
        for element in volumeElements(device, scope: scope) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var data = Float32(clamped)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &data)
        }
    }

    public static func setMuted(_ muted: Bool, _ direction: Direction) {
        guard let device = defaultDevice(direction) else { return }
        var address = propertyAddress(kAudioDevicePropertyMute, scope: scope(direction))
        guard AudioObjectHasProperty(device, &address) else { return }
        var data: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &data)
    }

    // MARK: - Leitura

    private static func defaultDevice(_ direction: Direction) -> AudioDeviceID? {
        let selector = direction == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        guard let device = try? getProperty(systemObject, selector, as: AudioDeviceID.self, default: 0),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func scope(_ direction: Direction) -> AudioObjectPropertyScope {
        direction == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }

    private static func mainVolumeAddress(_ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Volume "virtual" do dispositivo (o que o teclado usa); se não houver, o do canal principal ou a média dos canais.
    private static func volume(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        var main = mainVolumeAddress(scope)
        if AudioHardwareServiceHasProperty(device, &main) {
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioHardwareServiceGetPropertyData(device, &main, 0, nil, &size, &value) == noErr { return value }
        }
        let values: [Float] = volumeElements(device, scope: scope).compactMap { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    /// Elementos com volume ajustável: o principal, se tiver; senão os canais 1 e 2.
    private static func volumeElements(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        let settable: (AudioObjectPropertyElement) -> Bool = { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var flag: DarwinBoolean = false
            return AudioObjectHasProperty(device, &address)
                && AudioObjectIsPropertySettable(device, &address, &flag) == noErr && flag.boolValue
        }
        if settable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter(settable)
    }

    private static func muted(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
        var address = propertyAddress(kAudioDevicePropertyMute, scope: scope)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }
}
