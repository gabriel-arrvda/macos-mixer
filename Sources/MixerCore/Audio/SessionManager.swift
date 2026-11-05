import Foundation

/// Mantém uma `TapSession` por app que está tocando (ou parou há menos de 5 s) e expõe a lista pra UI.
///
/// Tudo roda na thread principal. A thread de áudio só enxerga o `GainControl` de cada sessão.
@MainActor
public final class SessionManager {
    public static let pollInterval: TimeInterval = 0.5
    public static let deviceChangeDelay: TimeInterval = 0.3
    public static let saveDelay: TimeInterval = 0.3

    /// Lista atualizada (ordem alfabética). Chamado a cada mudança.
    public var onEntriesChange: (([AppEntry]) -> Void)?
    /// A saída padrão mudou (já com o novo dispositivo).
    public var onOutputChange: ((OutputDevice) -> Void)?

    public private(set) var entries: [AppEntry] = []
    public private(set) var output: OutputDevice?

    private struct Slot {
        var group: AppGroup
        var session: TapSession?
        var status: SessionStatus
        /// Conjunto de processos com que a sessão foi (ou tentou ser) criada.
        var attemptedObjects: [UInt32]
    }

    private let store: VolumeStore
    private let now: () -> Date
    private let watcher = DeviceWatcher()
    private var presence: PresenceTracker
    private var slots: [String: Slot] = [:]
    private var settings: [String: AppVolume] = [:]
    private var dirtyKeys: Set<String> = []
    private var timer: Timer?
    private var deviceChangeWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?

    public init(store: VolumeStore = VolumeStore(), presence: PresenceTracker = PresenceTracker(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.presence = presence
        self.now = now
    }

    // MARK: - Ciclo de vida

    public func start() {
        guard timer == nil else { return }
        output = try? OutputDevice.current()
        watcher.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleDeviceRebuild() }
        }
        watcher.start()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Para tudo e devolve o áudio dos apps ao normal.
    public func stop() {
        timer?.invalidate()
        timer = nil
        watcher.stop()
        deviceChangeWork?.cancel()
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

    /// Tenta de novo as sessões que falharam.
    public func retryFailed() {
        for key in slots.keys where slots[key]?.status != .active && slots[key]?.session == nil {
            slots[key]?.attemptedObjects = []
        }
        refresh()
    }

    /// Maior amplitude de entrada de cada app desde a última leitura (0 = silêncio ou sem permissão).
    public func takePeaks() -> [String: Float] {
        slots.compactMapValues { $0.session?.gain.takePeak() }
    }

    // MARK: - Atualização

    func refresh() {
        guard let processes = try? ProcessDiscovery.snapshot() else { return }
        let resolver = OwnerResolver()
        let groups = ProcessGrouper.group(processes, excluding: SelfProcesses.pids(among: processes.map(\.pid)), resolver: resolver.owner(of:))
        apply(groups: groups)
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
        var slot = slots[key] ?? Slot(group: group, session: nil, status: .connecting, attemptedObjects: [])
        slot.group = group
        if slot.attemptedObjects != group.objectIDs {
            // Conjunto de processos novo (ou primeira vez): recria a sessão.
            slot.session?.stop()
            slot.session = nil
            slot.attemptedObjects = group.objectIDs
            do {
                guard let output = output ?? (try? OutputDevice.current()) else { throw AudioError("sem saída de áudio") }
                self.output = output
                slot.session = try TapSession(processObjects: group.objectIDs, outputUID: output.uid,
                                              fallbackSampleRate: output.nominalSampleRate(),
                                              initialGain: setting(for: key).effectiveGain)
                slot.status = .active
            } catch {
                slot.status = .failed("\(error)")
            }
        }
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
        for key in slots.keys {
            slots[key]?.session?.stop()
            slots[key]?.session = nil
            slots[key]?.attemptedObjects = []
            slots[key]?.status = .connecting
        }
        onOutputChange?(device)
        refresh()
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
                                isPlaying: slot.group.isPlaying, status: slot.status)
            }
        onEntriesChange?(entries)
    }
}
