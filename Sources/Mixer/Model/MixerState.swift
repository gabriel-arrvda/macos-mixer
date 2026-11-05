import Foundation
import MixerCore

/// Ponte entre o engine (`SessionManager`) e a UI. Sem engine (previews), os controles mexem só na lista local.
@MainActor
final class MixerState: ObservableObject {
    enum Signal: Equatable { case unknown, receiving, silent }

    @Published private(set) var entries: [AppEntry]
    @Published private(set) var output: OutputDevice?
    /// Nome do novo dispositivo, durante os 3 s do aviso de troca de saída.
    @Published private(set) var outputNotice: String?
    @Published private(set) var signal: Signal
    @Published private(set) var showsOnboarding: Bool
    /// Tela "Falta uma permissão".
    @Published var showsPermissionHelp: Bool

    private let manager: SessionManager?
    private let defaults: UserDefaults
    private var detector = SilenceDetector(threshold: AppConstants.silenceThreshold)
    private var peakTimer: Timer?
    private var noticeWork: DispatchWorkItem?

    init(manager: SessionManager?, defaults: UserDefaults = .standard,
         entries: [AppEntry] = [], output: OutputDevice? = nil, signal: Signal = .unknown,
         showsOnboarding: Bool? = nil, showsPermissionHelp: Bool = false, outputNotice: String? = nil) {
        self.manager = manager
        self.defaults = defaults
        self.entries = entries
        self.output = output
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
        output = manager.output
        manager.onEntriesChange = { [weak self] in self?.entries = $0 }
        manager.onOutputChange = { [weak self] in self?.outputChanged(to: $0) }
        manager.start()
        output = manager.output
        peakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSignal() }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: AppConstants.onboardingDoneKey)
        showsOnboarding = false
        startEngine()
    }

    func shutdown() {
        peakTimer?.invalidate()
        manager?.stop()
    }

    // MARK: - Controles

    func setVolume(_ volume: Float, for id: String) {
        if let manager { manager.setVolume(volume, for: id); return }
        update(id) { $0.volume = volume; $0.isMuted = false }
    }

    func toggleMute(for id: String) {
        if let manager { manager.toggleMute(for: id); return }
        update(id) { $0.isMuted.toggle() }
    }

    /// "Já ativei, tentar de novo".
    func retryAfterPermission() {
        showsPermissionHelp = false
        signal = .unknown
        manager?.retryFailed()
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
