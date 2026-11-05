import CoreAudio
import Foundation

/// Avisa (na fila principal) quando a saída padrão muda ou quando a taxa de amostragem
/// do dispositivo atual muda (acontece com Bluetooth ao trocar de perfil).
public final class DeviceWatcher {
    public var onChange: (() -> Void)?

    private var watchedDevice = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var rateListener: AudioObjectPropertyListenerBlock?

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
        watchSampleRate()
    }

    public func stop() {
        if let listener = defaultDeviceListener {
            var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, listener)
            defaultDeviceListener = nil
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
