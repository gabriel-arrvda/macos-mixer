import CoreAudio
import Foundation

/// Avisa (na fila principal) quando a saída padrão muda ou quando a taxa de amostragem
/// do dispositivo atual muda (acontece com Bluetooth ao trocar de perfil).
/// `onDevicesChange` avisa quando um dispositivo é conectado ou removido.
public final class DeviceWatcher {
    public var onChange: (() -> Void)?
    public var onDevicesChange: (() -> Void)?

    private var watchedDevice = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?

    public init() {}

    public func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.watchSampleRate()
            self?.onChange?()
        }
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(systemObject, &address, .main, listener)
        defaultDeviceListener = listener
        let devices: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onDevicesChange?() }
        var devicesAddress = propertyAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, .main, devices)
        devicesListener = devices
        watchSampleRate()
    }

    public func stop() {
        if let listener = defaultDeviceListener {
            var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, listener)
            defaultDeviceListener = nil
        }
        if let listener = devicesListener {
            var address = propertyAddress(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, listener)
            devicesListener = nil
        }
        unwatchSampleRate()
    }

    deinit { stop() }

    private func watchSampleRate() {
        unwatchSampleRate()
        guard let device = try? OutputDevice.current() else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onChange?() }
        var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
        AudioObjectAddPropertyListenerBlock(device.id, &address, .main, listener)
        watchedDevice = device.id
        rateListener = listener
    }

    private func unwatchSampleRate() {
        if let listener = rateListener, watchedDevice != kAudioObjectUnknown {
            var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(watchedDevice, &address, .main, listener)
        }
        rateListener = nil
        watchedDevice = AudioObjectID(kAudioObjectUnknown)
    }
}
