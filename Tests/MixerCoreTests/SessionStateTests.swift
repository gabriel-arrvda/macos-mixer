import AppKit
import XCTest
@testable import MixerCore

/// Engine falso: registra o que o `SessionManager` pede e deixa os testes injetarem pico e falhas.
final class FakeEngine: @unchecked Sendable {
    final class Session: AudioSession {
        let gain = GainControl(sampleRate: 48_000)
        let mode: SessionMode
        private(set) var stopped = false
        init(mode: SessionMode) { self.mode = mode }
        func stop() { stopped = true }
    }

    private(set) var requests: [SessionRequest] = []
    private(set) var sessions: [Session] = []
    var failuresLeft = 0
    var clock = Date(timeIntervalSince1970: 1_000)

    lazy var factory: SessionFactory = { [unowned self] request in
        self.requests.append(request)
        if self.failuresLeft > 0 {
            self.failuresLeft -= 1
            throw AudioError("falha de teste")
        }
        let session = Session(mode: request.mode)
        self.sessions.append(session)
        return session
    }

    var liveSessions: [Session] { sessions.filter { !$0.stopped } }
}

@MainActor
final class SessionStateTests: XCTestCase {
    private let owner = AppOwner(key: "com.x.app", name: "App", pid: 1)

    private func makeManager(_ engine: FakeEngine) -> SessionManager {
        let defaults = UserDefaults(suiteName: "state.\(UUID().uuidString)")!
        return SessionManager(store: VolumeStore(defaults: defaults, prefix: "t"),
                              now: { engine.clock }, factory: engine.factory)
    }

    private func group(_ objects: [UInt32], playing: [UInt32]? = nil, owner: AppOwner? = nil) -> AppGroup {
        AppGroup(owner: owner ?? self.owner, objectIDs: objects, isPlaying: !(playing ?? objects).isEmpty,
                 playingObjectIDs: playing ?? objects)
    }

    // MARK: - Tap em duas fases

    func testNewSessionStartsProbingAndStaysThereWithoutSignal() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10])])
        XCTAssertEqual(engine.requests.map(\.mode), [.probing])
        manager.pollSessions()                      // pico 0
        manager.pollSessions()
        XCTAssertEqual(engine.requests.map(\.mode), [.probing])
        XCTAssertFalse(manager.permissionConfirmed)
    }

    func testSignalConfirmsPermissionAndRebuildsAsActive() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10])])
        engine.sessions[0].gain.recordPeak(0.5)
        manager.pollSessions()
        XCTAssertTrue(manager.permissionConfirmed)
        XCTAssertEqual(engine.requests.map(\.mode), [.probing, .active])
        XCTAssertTrue(engine.sessions[0].stopped, "o tap de sondagem é desfeito")
        XCTAssertEqual(engine.liveSessions.count, 1)
    }

    func testNewSessionsAreBornActiveOnceConfirmed() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10])])
        engine.sessions[0].gain.recordPeak(0.5)
        manager.pollSessions()
        let other = AppOwner(key: "com.y.app", name: "Outro", pid: 2)
        manager.apply(groups: [group([10]), group([20], owner: other)])
        XCTAssertEqual(engine.requests.last?.mode, .active)
        XCTAssertEqual(engine.requests.count, 3)
    }

    func testActiveSessionThatGoesSilentFallsBackToProbing() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10])])
        engine.sessions[0].gain.recordPeak(0.5)
        manager.pollSessions()
        let active = engine.sessions[1]
        manager.demoteToProbing()
        XCTAssertTrue(active.stopped, "o tap que silencia o original é desfeito")
        XCTAssertEqual(engine.requests.last?.mode, .probing)
        XCTAssertFalse(manager.permissionConfirmed)
        XCTAssertEqual(engine.liveSessions.count, 1)
    }

    func testTakePeaksSeesProbePeakConsumedByPoll() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10])])
        engine.sessions[0].gain.recordPeak(0.4)
        manager.pollSessions()
        XCTAssertEqual(manager.takePeaks()[owner.key] ?? 0, 0, accuracy: 1e-6, "sessão recriada começa sem pico")
    }

    /// A sondagem só mede: a saída fica exatamente como o Core Audio entregou.
    func testProbingNeverWritesToOutput() {
        let gain = GainControl(sampleRate: 48_000, initialGain: 1)
        let list = AudioBufferListHelper(frames: 4, channels: 2, value: 0.6)
        gain.processProbe(input: list.input)
        XCTAssertEqual(list.outputSamples, [Float](repeating: -9, count: 8))
        XCTAssertEqual(gain.takePeak(), 0.6, accuracy: 1e-6)
    }

    // MARK: - Recriação

    func testIdleProcessChangesDoNotRecreate() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10, 11], playing: [10])])
        manager.apply(groups: [group([10, 11, 12], playing: [10])])   // chegou um processo ocioso
        manager.apply(groups: [group([10], playing: [10])])            // um ocioso saiu
        manager.apply(groups: [group([10, 11], playing: [])])          // o que tocava parou
        XCTAssertEqual(engine.requests.count, 1)
    }

    func testNewPlayingProcessRecreates() {
        let engine = FakeEngine()
        let manager = makeManager(engine)
        manager.apply(groups: [group([10], playing: [10])])
        manager.apply(groups: [group([10, 11], playing: [10, 11])])
        XCTAssertEqual(engine.requests.count, 2)
        XCTAssertEqual(engine.requests[1].objects, [10, 11])
        XCTAssertTrue(engine.sessions[0].stopped)
    }

    // MARK: - Falha e nova tentativa

    func testFailedSessionRetriesWithBackoffThenGivesUp() {
        let engine = FakeEngine()
        engine.failuresLeft = 99
        let manager = makeManager(engine)
        let g = group([10])
        manager.apply(groups: [g])
        XCTAssertEqual(manager.entries.first?.status, .connecting)
        manager.apply(groups: [g])                       // ainda dentro do 1 s
        XCTAssertEqual(engine.requests.count, 1)
        for (index, wait) in SessionManager.retryBackoff.enumerated() {
            engine.clock.addTimeInterval(wait + 0.1)
            manager.apply(groups: [g])
            XCTAssertEqual(engine.requests.count, index + 2)
        }
        guard case .failed = manager.entries.first?.status else { return XCTFail("esperava .failed") }
        engine.clock.addTimeInterval(60)
        manager.apply(groups: [g])
        XCTAssertEqual(engine.requests.count, 4, "depois de 3 retentativas não tenta mais sozinho")
    }

    func testRetryFailedStartsOver() {
        let engine = FakeEngine()
        engine.failuresLeft = 4
        let manager = makeManager(engine)
        let g = group([10])
        manager.apply(groups: [g])
        for wait in SessionManager.retryBackoff { engine.clock.addTimeInterval(wait + 0.1); manager.apply(groups: [g]) }
        guard case .failed = manager.entries.first?.status else { return XCTFail() }
        manager.retryFailed()                            // refresh() real descobre processos; só confere o reset
        manager.apply(groups: [g])
        XCTAssertEqual(manager.entries.first?.status, .active)
        manager.stop()
    }

    func testSuccessAfterTransientFailure() {
        let engine = FakeEngine()
        engine.failuresLeft = 1
        let manager = makeManager(engine)
        let g = group([10])
        manager.apply(groups: [g])
        engine.clock.addTimeInterval(1.1)
        manager.apply(groups: [g])
        XCTAssertEqual(manager.entries.first?.status, .active)
    }

    // MARK: - Encerramento

    func testTerminationNotificationFlushesSettingsAndStopsSessions() {
        let engine = FakeEngine()
        let defaults = UserDefaults(suiteName: "term.\(UUID().uuidString)")!
        let store = VolumeStore(defaults: defaults, prefix: "t")
        let manager = SessionManager(store: store, now: { engine.clock }, factory: engine.factory)
        manager.apply(groups: [group([10])])
        manager.installTerminationObserver()
        manager.setVolume(0.4, for: owner.key)
        XCTAssertEqual(store.load(owner.key).volume, 1, "ainda no debounce")
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))   // menos que os 0,3 s do debounce
        XCTAssertEqual(store.load(owner.key).volume, 0.4, accuracy: 0.001)
        XCTAssertTrue(engine.liveSessions.isEmpty)
    }
}

final class BufferSelectionTests: XCTestCase {
    func testOnlyTap() throws {
        XCTAssertEqual(try BufferSelection.tapInputIndex(inputChannels: [2], tapChannels: 2), 0)
    }

    func testTapPlusMonoMicrophoneInEitherOrder() throws {
        XCTAssertEqual(try BufferSelection.tapInputIndex(inputChannels: [1, 2], tapChannels: 2), 1)
        XCTAssertEqual(try BufferSelection.tapInputIndex(inputChannels: [2, 1], tapChannels: 2), 0)
    }

    func testTapPlusStereoMicrophoneIsAmbiguous() {
        XCTAssertThrowsError(try BufferSelection.tapInputIndex(inputChannels: [2, 2], tapChannels: 2))
    }

    func testNoMatchingBufferFails() {
        XCTAssertThrowsError(try BufferSelection.tapInputIndex(inputChannels: [1], tapChannels: 2))
        XCTAssertThrowsError(try BufferSelection.tapInputIndex(inputChannels: [], tapChannels: 2))
    }
}

final class OwnerPathTests: XCTestCase {
    func testTopLevelBundleOnly() {
        XCTAssertTrue(OwnerResolver.isTopLevelBundle("/Applications/Bartender.app"))
        XCTAssertFalse(OwnerResolver.isTopLevelBundle("/Applications/Chrome.app/Contents/Frameworks/Helper.app"))
        XCTAssertFalse(OwnerResolver.isTopLevelBundle(nil))
    }
}

final class MonoMixdownTests: XCTestCase {
    func testStereoToMonoAveragesChannels() {
        let source: [Float] = [1, 0, 0.2, 0.4]   // 2 frames estéreo
        var out = [Float](repeating: -9, count: 2)
        var peak: Float = 0
        _ = GainControl.apply(source: source, destination: &out, frames: 2, sourceChannels: 2,
                              destinationChannels: 1, startGain: 1, targetGain: 1, step: 0.1, peak: &peak)
        XCTAssertEqual(out[0], 0.5, accuracy: 1e-6)   // o canal direito não é descartado
        XCTAssertEqual(out[1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(peak, 1)
    }

    func testRightOnlySignalSurvivesMono() {
        var out: [Float] = [0]
        var peak: Float = 0
        _ = GainControl.apply(source: [0, 0.8], destination: &out, frames: 1, sourceChannels: 2,
                              destinationChannels: 1, startGain: 1, targetGain: 1, step: 0.1, peak: &peak)
        XCTAssertEqual(out[0], 0.4, accuracy: 1e-6)
    }
}
