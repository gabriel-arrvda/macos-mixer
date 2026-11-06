import Foundation
import MixerCore

/// Ponte entre o engine (`SessionManager`) e a UI. Sem engine (previews), os controles mexem só no estado local.
@MainActor
final class MixerState: ObservableObject {
    enum Signal: Equatable { case unknown, receiving, silent }

    @Published private(set) var entries: [AppEntry]
    @Published private(set) var output: OutputDevice?
    @Published private(set) var devices: [OutputDevice]
    /// Volume e mudo da saída padrão e do microfone padrão (controles do próprio dispositivo).
    @Published private(set) var systemOutput: DeviceVolume
    @Published private(set) var microphone: DeviceVolume
    /// Nome do novo dispositivo, durante os 3 s do aviso de troca de saída.
    @Published private(set) var outputNotice: String?
    @Published private(set) var signal: Signal
    @Published private(set) var showsOnboarding: Bool
    /// Tela "Falta uma permissão".
    @Published var showsPermissionHelp: Bool

    private(set) lazy var levels = LevelMonitor { [weak self] in self?.currentLevels() ?? [:] }

    private let manager: SessionManager?
    private let defaults: UserDefaults
    private var detector = SilenceDetector(threshold: AppConstants.silenceThreshold)
    private var peakTimer: Timer?
    private var noticeWork: DispatchWorkItem?

    init(manager: SessionManager?, defaults: UserDefaults = .standard,
         entries: [AppEntry] = [], output: OutputDevice? = nil, devices: [OutputDevice] = [],
         systemOutput: DeviceVolume = .unavailable, microphone: DeviceVolume = .unavailable,
         signal: Signal = .unknown, showsOnboarding: Bool? = nil, showsPermissionHelp: Bool = false,
         outputNotice: String? = nil) {
        self.manager = manager
        self.defaults = defaults
        self.entries = entries
        self.output = output
        self.devices = devices
        self.systemOutput = systemOutput
        self.microphone = microphone
        self.signal = signal
        self.showsOnboarding = showsOnboarding ?? !defaults.bool(forKey: AppConstants.onboardingDoneKey)
        self.showsPermissionHelp = showsPermissionHelp
        self.outputNotice = outputNotice
    }

    static func live() -> MixerState {
        let state = MixerState(manager: SessionManager())
        if !state.showsOnboarding { state.startEngine() }
        return state
    }

    var needsAttention: Bool { showsOnboarding || showsPermissionHelp || signal == .silent }

    // MARK: - Ciclo de vida

    /// Só começa depois da primeira execução: é quando o macOS vai pedir a permissão, ao primeiro app tocar.
    private func startEngine() {
        guard let manager else { return }
        manager.onEntriesChange = { [weak self] in self?.entries = $0 }
        manager.onOutputChange = { [weak self] in self?.outputChanged(to: $0) }
        manager.onDevicesChange = { [weak self] in self?.devices = $0 }
        manager.start()
        output = manager.output
        devices = manager.devices
        refreshSystemAudio()
        peakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkSignal()
                self?.refreshSystemAudio()
            }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: AppConstants.onboardingDoneKey)
        showsOnboarding = false
        startEngine()
    }

    func shutdown() {
        peakTimer?.invalidate()
        levels.stop()
        manager?.stop()
    }

    // MARK: - Controles por app

    func setVolume(_ volume: Float, for id: String) {
        if let manager { manager.setVolume(volume, for: id); return }
        update(id) { $0.volume = AppVolume.clamp(volume); $0.isMuted = false }
    }

    func setMuted(_ muted: Bool, for id: String) {
        if let manager { manager.setMuted(muted, for: id); return }
        update(id) { $0.isMuted = muted }
    }

    func toggleMute(for id: String) {
        if let manager { manager.toggleMute(for: id); return }
        update(id) { $0.isMuted.toggle() }
    }

    /// `nil` = segue a saída padrão.
    func setOutput(_ uid: String?, for id: String) {
        if let manager { manager.setOutput(uid, for: id); return }
        update(id) { $0.outputUID = uid == output?.uid ? nil : uid }
    }

    // MARK: - Saída e microfone do sistema

    func setSystemOutput(_ device: OutputDevice) {
        if let manager { manager.setSystemOutput(device); return }
        output = device
    }

    func setSystemVolume(_ volume: Float, _ direction: SystemAudio.Direction) {
        if manager != nil {
            SystemAudio.setVolume(volume, direction)
            if direction == .output, systemOutput.isMuted == true { SystemAudio.setMuted(false, .output) }
            if direction == .input, microphone.isMuted == true { SystemAudio.setMuted(false, .input) }
            refreshSystemAudio()
        } else {
            modify(direction) { $0.volume = min(max(volume, 0), 1); if $0.isMuted != nil { $0.isMuted = false } }
        }
    }

    func toggleSystemMute(_ direction: SystemAudio.Direction) {
        let current = direction == .output ? systemOutput : microphone
        guard let muted = current.isMuted else { return }
        if manager != nil {
            SystemAudio.setMuted(!muted, direction)
            refreshSystemAudio()
        } else {
            modify(direction) { $0.isMuted = !muted }
        }
    }

    private func refreshSystemAudio() {
        guard manager != nil else { return }
        let out = SystemAudio.read(.output), mic = SystemAudio.read(.input)
        if out != systemOutput { systemOutput = out }
        if mic != microphone { microphone = mic }
    }

    private func modify(_ direction: SystemAudio.Direction, _ change: (inout DeviceVolume) -> Void) {
        if direction == .output { change(&systemOutput) } else { change(&microphone) }
    }

    /// "Já ativei, tentar de novo".
    func retryAfterPermission() {
        showsPermissionHelp = false
        signal = .unknown
        manager?.retryFailed()
    }

    // MARK: - Medidores

    private func currentLevels() -> [String: Float] {
        if let manager { return manager.takeLevels() }
        // Previews: nível falso proporcional ao volume, pra ver o medidor mexendo.
        var fake: [String: Float] = [:]
        for entry in entries where entry.isPlaying && !entry.isMuted {
            fake[entry.id] = min(1, entry.volume * 0.55 * Float.random(in: 0.6...1.1))
        }
        return fake
    }

    // MARK: - Sinal e saída

    private func checkSignal() {
        guard let manager else { return }
        let peaks = manager.takePeaks()
        let active = entries.filter { $0.status == .active && $0.isPlaying }
        switch detector.update(peaks: active.map { peaks[$0.id] ?? 0 }, now: Date()) {
        case .receiving: signal = .receiving
        case .silent:
            signal = .silent
            // Desfaz os taps que silenciam o original e volta a sondar: sem permissão, o app não pode ficar mudo.
            manager.demoteToProbing()
            detector = SilenceDetector(threshold: AppConstants.silenceThreshold)
        case .idle: if signal == .silent { signal = .unknown }
        case .pending: break
        }
    }

    private func outputChanged(to device: OutputDevice) {
        output = device
        refreshSystemAudio()
        outputNotice = device.name
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.outputNotice = nil }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.outputNoticeDuration, execute: work)
    }

    private func update(_ id: String, _ change: (inout AppEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }
}
