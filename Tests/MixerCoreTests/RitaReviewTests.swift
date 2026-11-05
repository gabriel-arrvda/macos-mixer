import XCTest
@testable import MixerCore

@MainActor
final class RitaReviewTests: XCTestCase {
    private func makeStore() -> VolumeStore {
        let suite = "rita.review.\(UUID().uuidString)"
        return VolumeStore(defaults: UserDefaults(suiteName: suite)!, prefix: "t")
    }

    /// Salvamento é adiado 0,3 s: sem stop()/flush antes de sair, o ajuste se perde.
    func testVolumeIsOnlyPersistedAfterFlush() {
        let store = makeStore()
        let manager = SessionManager(store: store)
        manager.setVolume(0.4, for: "com.x.app")
        XCTAssertEqual(store.load("com.x.app").volume, 1, "ainda não gravou (debounce)")
        manager.stop()
        XCTAssertEqual(store.load("com.x.app").volume, 0.4, accuracy: 0.001)
    }

    func testDragWhileMutedUnmutesAndKeepsDraggedVolume() {
        let store = makeStore()
        let manager = SessionManager(store: store)
        manager.setMuted(true, for: "a")
        manager.setVolume(0.7, for: "a")
        manager.stop()
        let v = store.load("a")
        XCTAssertFalse(v.isMuted)
        XCTAssertEqual(v.volume, 0.7, accuracy: 0.001)
    }

    /// Sessão que falha (objeto inexistente) vira .failed e não é refeita no próximo ciclo.
    func testFailedSessionIsNotRetriedUntilObjectsChange() {
        let manager = SessionManager(store: makeStore())
        let owner = AppOwner(key: "fake.app", name: "Fake", pid: 99999)
        let group = AppGroup(owner: owner, objectIDs: [4_000_000], isPlaying: true)
        manager.apply(groups: [group])
        guard case .failed = manager.entries.first?.status else { return XCTFail("esperava .failed: \(String(describing: manager.entries.first?.status))") }
        manager.apply(groups: [group])
        guard case .failed = manager.entries.first?.status else { return XCTFail() }
        manager.stop()
    }
}
