import XCTest
@testable import MixerCore

@MainActor
final class RitaReviewTests: XCTestCase {
    private func makeStore() -> VolumeStore {
        let suite = "rita.review.\(UUID().uuidString)"
        return VolumeStore(defaults: UserDefaults(suiteName: suite)!, prefix: "t")
    }

    /// Salvamento é adiado 0,3 s: só o stop()/flush grava. O encerramento chama stop() (ver SessionStateTests).
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
}
