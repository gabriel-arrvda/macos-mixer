import AppKit
import Foundation

/// Fábrica de verdade: tap, aggregate device e IOProc na saída pedida (ou na padrão de agora).
public enum LiveSessions {
    public static let factory: SessionFactory = { request in
        let output = try request.outputUID.flatMap(OutputDevice.device(uid:)) ?? OutputDevice.current()
        return try TapSession(processObjects: request.objects, outputUID: output.uid,
                              fallbackSampleRate: output.nominalSampleRate(),
                              initialGain: request.initialGain, mode: request.mode)
    }
}

/// Pedido de criação de sessão (o que a fábrica precisa saber).
public struct SessionRequest {
    public let objects: [UInt32]
    public let mode: SessionMode
    public let initialGain: Float
    /// UID da saída escolhida pro app. `nil` = saída padrão.
    public let outputUID: String?
}

public typealias SessionFactory = (SessionRequest) throws -> AudioSession

/// Mantém uma `TapSession` por app que está tocando (ou parou há menos de 5 s) e expõe a lista pra UI.
///
/// Tudo roda na thread principal. A thread de áudio só enxerga o `GainControl` de cada sessão.
@MainActor
public final class SessionManager {
    public static let pollInterval: TimeInterval = 0.5
    public static let deviceChangeDelay: TimeInterval = 0.3
    public static let saveDelay: TimeInterval = 0.3
    /// Esperas antes de cada nova tentativa de uma sessão que falhou (1 s, 2 s, 4 s). Depois disso vira `.failed`.
    public static let retryBackoff: [TimeInterval] = [1, 2, 4]

    /// Lista atualizada (ordem alfabética). Chamado a cada mudança.
    public var onEntriesChange: (([AppEntry]) -> Void)?
    /// A saída padrão mudou (já com o novo dispositivo).
    public var onOutputChange: ((OutputDevice) -> Void)?
    /// Um dispositivo de saída foi conectado ou removido.
    public var onDevicesChange: (([OutputDevice]) -> Void)?

    public private(set) var entries: [AppEntry] = []
    public private(set) var output: OutputDevice?
    /// Saídas disponíveis pra escolher, por app ou pro sistema.
    public private(set) var devices: [OutputDevice] = []
    /// Verdadeiro depois que algum tap recebeu sinal diferente de zero: a permissão existe.
    /// Não é persistido, porque um rebuild pode perder a permissão.
    public private(set) var permissionConfirmed = false

    private struct Slot {
        var group: AppGroup
        var session: AudioSession?
        var mode: SessionMode
        var status: SessionStatus
        /// Processos que o tap atual cobre.
        var coveredObjects: Set<UInt32>
        /// Nenhuma tentativa ainda (ou pedido de recomeço).
        var needsSession: Bool
        var failures: Int
        var retryAt: Date?
        /// Maior pico de entrada desde a última leitura de `takePeaks`.
        var peak: Float
    }

    private let store: VolumeStore
    private let factory: SessionFactory
    private let now: () -> Date
    private let watcher = DeviceWatcher()
    private var presence: PresenceTracker
    private var slots: [String: Slot] = [:]
    private var settings: [String: AppVolume] = [:]
    private var routes: [String: String?] = [:]
    private var devicesChangeWork: DispatchWorkItem?
    private var dirtyKeys: Set<String> = []
    private var timer: Timer?
    private var deviceChangeWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?

    public init(store: VolumeStore = VolumeStore(), presence: PresenceTracker = PresenceTracker(),
                now: @escaping () -> Date = Date.init,
                factory: @escaping SessionFactory = LiveSessions.factory) {
        self.store = store
        self.factory = factory
        self.presence = presence
        self.now = now
    }

    // MARK: - Ciclo de vida

    public func start() {
        guard timer == nil else { return }
        installTerminationObserver()
        output = try? OutputDevice.current()
        devices = OutputDevice.all()
        watcher.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleDeviceRebuild() }
        }
        watcher.onDevicesChange = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleDevicesRefresh() }
        }
        watcher.start()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Ao sair do app (inclusive por "Sair"), grava os ajustes pendentes e desfaz os taps.
    func installTerminationObserver() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// Para tudo e devolve o áudio dos apps ao normal.
    public func stop() {
        timer?.invalidate()
        timer = nil
        watcher.stop()
        deviceChangeWork?.cancel()
        devicesChangeWork?.cancel()
        flushSettings()
        slots.values.forEach { $0.session?.stop() }
        slots.removeAll()
        publish()
    }

    // MARK: - Controles

    /// Mexer no slider tira o app do mudo, e o valor arrastado vira o volume.
    public func setVolume(_ volume: Float, for key: String) {
        var value = setting(for: key)
        value.volume = GainControl.clamp(volume)
        value.isMuted = false
        update(value, for: key)
    }

    public func setMuted(_ muted: Bool, for key: String) {
        var value = setting(for: key)
        value.isMuted = muted
        update(value, for: key)
    }

    public func toggleMute(for key: String) {
        setMuted(!setting(for: key).isMuted, for: key)
    }

    /// Escolhe em qual saída o app toca. `nil`, ou a própria saída padrão, volta a seguir o sistema.
    /// A sessão é recriada na hora no novo dispositivo.
    public func setOutput(_ uid: String?, for key: String) {
        let normalized = (uid == nil || uid == output?.uid) ? nil : uid
        guard route(for: key) != normalized else { return }
        routes[key] = .some(normalized)
        store.saveOutput(normalized, for: key)
        if let mode = slots[key]?.mode { rebuild(key, mode: mode) }
        publish()
    }

    /// Troca a saída padrão do sistema. Os apps que seguem o padrão vão junto (via `DeviceWatcher`).
    public func setSystemOutput(_ device: OutputDevice) {
        try? OutputDevice.setDefault(device)
    }

    /// Tenta de novo as sessões que desistiram de vez.
    public func retryFailed() {
        for key in slots.keys {
            guard case .failed = slots[key]?.status else { continue }
            slots[key]?.needsSession = true
            slots[key]?.failures = 0
            slots[key]?.retryAt = nil
        }
        refresh()
    }

    /// Maior amplitude de entrada de cada app desde a última leitura (0 = silêncio ou sem permissão).
    /// É o único leitor do pico das sessões: a sondagem e a UI usam o mesmo valor.
    public func takePeaks() -> [String: Float] {
        var result: [String: Float] = [:]
        for key in slots.keys where slots[key]?.session != nil {
            result[key] = slots[key]?.peak
            slots[key]?.peak = 0
        }
        return result
    }

    /// Nível de saída de cada app (0...1, depois do ganho) desde a última leitura. Só pro medidor da UI.
    public func takeLevels() -> [String: Float] {
        var result: [String: Float] = [:]
        for (key, slot) in slots { if let session = slot.session { result[key] = session.gain.takeLevel() } }
        return result
    }

    /// O sinal sumiu em todos os apps ativos: desfaz os taps que silenciam o original e volta a sondar.
    /// Assim o app deixa de ficar mudo se a permissão foi perdida.
    public func demoteToProbing() {
        permissionConfirmed = false
        for key in slots.keys where slots[key]?.mode == .active && slots[key]?.session != nil {
            rebuild(key, mode: .probing)
        }
        publish()
    }

    // MARK: - Atualização

    func refresh() {
        guard let processes = try? ProcessDiscovery.snapshot() else { return }
        let resolver = OwnerResolver()
        let groups = ProcessGrouper.group(processes, excluding: SelfProcesses.pids(among: processes.map(\.pid)), resolver: resolver.owner(of:))
        apply(groups: groups)
        pollSessions()
    }

    /// Lê o pico de cada sessão. Na sondagem, pico acima de zero confirma a permissão: a partir daí
    /// todas as sessões passam a `.active` (com mudo do original) e as novas já nascem assim.
    func pollSessions() {
        var sawSignal = false
        for key in slots.keys {
            guard let session = slots[key]?.session else { continue }
            let peak = session.gain.takePeak()
            let previous = slots[key]?.peak ?? 0
            slots[key]?.peak = max(previous, peak)
            if slots[key]?.mode == .probing, peak > SilenceDetector.silenceThreshold { sawSignal = true }
        }
        guard sawSignal, !permissionConfirmed else { return }
        permissionConfirmed = true
        for key in slots.keys where slots[key]?.mode == .probing && slots[key]?.session != nil {
            rebuild(key, mode: .active)
        }
        publish()
    }

    /// Separado de `refresh` pra poder alimentar com dados falsos.
    func apply(groups: [AppGroup]) {
        let byKey = Dictionary(groups.map { ($0.owner.key, $0) }, uniquingKeysWith: { first, _ in first })
        let active = Set(groups.filter(\.isPlaying).map(\.owner.key))
        let visible = presence.update(active: active, now: now())

        // Quem saiu da lista (passou dos 5 s, ou o app fechou) perde o tap.
        for key in slots.keys where !visible.contains(key) {
            slots[key]?.session?.stop()
            slots[key] = nil
        }
        // Quem está visível mas sumiu da lista do Core Audio (processo encerrado) mantém a linha
        // até acabar a tolerância; só quem ainda existe ganha ou mantém sessão.
        for key in visible {
            if let group = byKey[key] { ensureSession(for: group) }
        }
        publish()
    }

    private func ensureSession(for group: AppGroup) {
        let key = group.owner.key
        var slot = slots[key] ?? Slot(group: group, session: nil, mode: .probing, status: .connecting,
                                      coveredObjects: [], needsSession: true, failures: 0, retryAt: nil, peak: 0)
        slot.group = group
        // Só um processo tocando que o tap atual ainda não cobre derruba a sessão. Mudança em processo
        // ocioso, ou um que parou de tocar, mantém o tap: recriar faria o app voltar a tocar sem ganho.
        if !slot.needsSession, slot.session != nil, !slot.coveredObjects.isSuperset(of: group.playingObjectIDs) {
            slot.needsSession = true
            slot.failures = 0
            slot.retryAt = nil
        }
        let retryDue = slot.session == nil && slot.status == .connecting && !slot.needsSession
            && (slot.retryAt.map { now() >= $0 } ?? false)
        if slot.needsSession || retryDue {
            slot.session?.stop()
            slot.session = nil
            attempt(&slot, key: key, mode: permissionConfirmed ? .active : .probing)
        }
        slots[key] = slot
    }

    /// Cria a sessão. Falha vira nova tentativa com espera crescente; esgotadas as tentativas, `.failed`.
    private func attempt(_ slot: inout Slot, key: String, mode: SessionMode) {
        slot.needsSession = false
        slot.mode = mode
        slot.peak = 0
        let objects = slot.group.objectIDs
        do {
            slot.session = try factory(SessionRequest(objects: objects, mode: mode,
                                                      initialGain: setting(for: key).effectiveGain,
                                                      outputUID: availableRoute(for: key)))
            slot.coveredObjects = Set(objects)
            slot.status = .active
            slot.failures = 0
            slot.retryAt = nil
        } catch {
            slot.failures += 1
            if slot.failures > Self.retryBackoff.count {
                slot.status = .failed("\(error)")
                slot.retryAt = nil
            } else {
                slot.status = .connecting
                slot.retryAt = now().addingTimeInterval(Self.retryBackoff[slot.failures - 1])
            }
        }
    }

    /// Troca a sessão de um app por outra na fase pedida, mantendo o resto do estado.
    private func rebuild(_ key: String, mode: SessionMode) {
        guard var slot = slots[key] else { return }
        slot.session?.stop()
        slot.session = nil
        attempt(&slot, key: key, mode: mode)
        slots[key] = slot
    }

    // MARK: - Troca de dispositivo

    private func scheduleDeviceRebuild() {
        deviceChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildForNewDevice() }
        }
        deviceChangeWork = work
        // Troca de saída gera uma rajada de eventos; espera assentar.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deviceChangeDelay, execute: work)
    }

    private func rebuildForNewDevice() {
        guard let device = try? OutputDevice.current() else { return }
        output = device
        // Quem tem saída própria (e conectada) não muda; só quem segue o padrão é recriado.
        for key in slots.keys where availableRoute(for: key) == nil {
            slots[key]?.session?.stop()
            slots[key]?.session = nil
            slots[key]?.needsSession = true
            slots[key]?.failures = 0
            slots[key]?.retryAt = nil
            slots[key]?.status = .connecting
        }
        onOutputChange?(device)
        refresh()
    }

    private func scheduleDevicesRefresh() {
        devicesChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshDevices(OutputDevice.all()) }
        }
        devicesChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deviceChangeDelay, execute: work)
    }

    /// Atualiza a lista de saídas. App cuja saída escolhida sumiu (ou voltou) é recriado.
    func refreshDevices(_ list: [OutputDevice]) {
        guard list != devices else { return }
        let before = Dictionary(uniqueKeysWithValues: slots.keys.map { ($0, availableRoute(for: $0)) })
        devices = list
        for (key, previous) in before where availableRoute(for: key) != previous {
            if let mode = slots[key]?.mode { rebuild(key, mode: mode) }
        }
        onDevicesChange?(devices)
        publish()
    }

    // MARK: - Saída por app

    private func route(for key: String) -> String? {
        if let cached = routes[key] { return cached }
        let loaded = store.loadOutput(key)
        routes[key] = .some(loaded)
        return loaded
    }

    /// A saída escolhida, se ainda estiver conectada. Antes de `start` (lista vazia), confia no que foi salvo.
    private func availableRoute(for key: String) -> String? {
        guard let uid = route(for: key) else { return nil }
        return devices.isEmpty || devices.contains(where: { $0.uid == uid }) ? uid : nil
    }

    // MARK: - Volume

    private func setting(for key: String) -> AppVolume {
        if let cached = settings[key] { return cached }
        let loaded = store.load(key)
        settings[key] = loaded
        return loaded
    }

    private func update(_ value: AppVolume, for key: String) {
        settings[key] = value
        slots[key]?.session?.gain.setTarget(value.isMuted ? 0 : value.volume)
        dirtyKeys.insert(key)
        scheduleSave()
        publish()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushSettings() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func flushSettings() {
        saveWork?.cancel()
        for key in dirtyKeys { if let value = settings[key] { store.save(value, for: key) } }
        dirtyKeys.removeAll()
    }

    private func publish() {
        entries = slots.values
            .sorted { lhs, rhs in
                let order = lhs.group.owner.name.localizedCaseInsensitiveCompare(rhs.group.owner.name)
                return order == .orderedSame ? lhs.group.owner.key < rhs.group.owner.key : order == .orderedAscending
            }
            .map { slot in
                let value = setting(for: slot.group.owner.key)
                return AppEntry(owner: slot.group.owner, volume: value.volume, isMuted: value.isMuted,
                                isPlaying: slot.group.isPlaying, status: slot.status,
                                outputUID: availableRoute(for: slot.group.owner.key))
            }
        onEntriesChange?(entries)
    }
}
