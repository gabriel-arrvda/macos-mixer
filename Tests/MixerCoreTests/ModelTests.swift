import XCTest
@testable import MixerCore

final class ProcessGrouperTests: XCTestCase {
    private func process(_ object: UInt32, pid: pid_t, running: Bool = false) -> AudioProcessInfo {
        AudioProcessInfo(objectID: object, pid: pid, bundleID: nil, isRunningOutput: running)
    }

    private let chrome = AppOwner(key: "com.google.Chrome", name: "Google Chrome", pid: 100)
    private let safari = AppOwner(key: "com.apple.Safari", name: "Safari", pid: 200)
    private let spotify = AppOwner(key: "com.spotify.client", name: "spotify", pid: 300)

    func testHelpersAreGroupedUnderOwner() {
        let owners: [pid_t: AppOwner] = [100: chrome, 101: chrome, 102: chrome, 201: safari]
        let groups = ProcessGrouper.group([
            process(1, pid: 100), process(2, pid: 101, running: true), process(3, pid: 102), process(4, pid: 201),
        ], resolver: { owners[$0.pid] })
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].owner, chrome)
        XCTAssertEqual(groups[0].objectIDs, [1, 2, 3])
        XCTAssertTrue(groups[0].isPlaying)       // basta um helper tocando
        XCTAssertFalse(groups[1].isPlaying)
    }

    func testOrderIsAlphabeticalIgnoringCaseAndStable() {
        let owners: [pid_t: AppOwner] = [1: spotify, 2: safari, 3: chrome]
        let processes = [process(1, pid: 1), process(2, pid: 2), process(3, pid: 3)]
        let names = ProcessGrouper.group(processes, resolver: { owners[$0.pid] }).map(\.owner.name)
        XCTAssertEqual(names, ["Google Chrome", "Safari", "spotify"])
        XCTAssertEqual(ProcessGrouper.group(processes.reversed(), resolver: { owners[$0.pid] }).map(\.owner.name), names)
    }

    func testProcessesWithoutOwnerAndExcludedPIDsAreDropped() {
        let owners: [pid_t: AppOwner] = [100: chrome]
        let groups = ProcessGrouper.group([process(1, pid: 100), process(2, pid: 999), process(3, pid: 50)],
                                          excluding: [50], resolver: { owners[$0.pid] })
        XCTAssertEqual(groups.map(\.owner), [chrome])
    }

    func testOwnerThatIsExcludedDropsItsHelpers() {
        let mine = AppOwner(key: "me", name: "Mixer", pid: 50)
        let groups = ProcessGrouper.group([process(1, pid: 51)], excluding: [50], resolver: { _ in mine })
        XCTAssertTrue(groups.isEmpty)
    }
}

final class PresenceTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    func testKeepsAppForGraceAfterItStops() {
        var tracker = PresenceTracker(grace: 5)
        XCTAssertEqual(tracker.update(active: ["a"], now: t0), ["a"])
        XCTAssertEqual(tracker.update(active: [], now: t0 + 4.9), ["a"])
        XCTAssertEqual(tracker.update(active: [], now: t0 + 5.1), [])
    }

    func testReturningToPlayRestartsGrace() {
        var tracker = PresenceTracker(grace: 5)
        _ = tracker.update(active: ["a"], now: t0)
        _ = tracker.update(active: ["a"], now: t0 + 4)
        XCTAssertEqual(tracker.update(active: [], now: t0 + 8), ["a"])
        XCTAssertEqual(tracker.update(active: [], now: t0 + 9.5), [])
    }

    func testAppsAreIndependent() {
        var tracker = PresenceTracker(grace: 5)
        _ = tracker.update(active: ["a", "b"], now: t0)
        XCTAssertEqual(tracker.update(active: ["b"], now: t0 + 6), ["b"])
    }
}

final class VolumeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mixer.tests.\(UUID().uuidString)"

    override func setUp() { defaults = UserDefaults(suiteName: suite) }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDefaultsToFullVolumeNotMuted() {
        XCTAssertEqual(VolumeStore(defaults: defaults).load("com.apple.Safari"), AppVolume(volume: 1, isMuted: false))
    }

    func testSaveAndLoadPerApp() {
        let store = VolumeStore(defaults: defaults)
        store.save(AppVolume(volume: 0.35, isMuted: true), for: "a")
        store.save(AppVolume(volume: 0.8, isMuted: false), for: "b")
        let reopened = VolumeStore(defaults: defaults)
        XCTAssertEqual(reopened.load("a").volume, 0.35, accuracy: 1e-6)
        XCTAssertTrue(reopened.load("a").isMuted)
        XCTAssertEqual(reopened.load("b"), AppVolume(volume: 0.8, isMuted: false))
    }

    func testMutedKeepsPreviousVolumeAndZeroIsNotMuted() {
        let store = VolumeStore(defaults: defaults)
        store.save(AppVolume(volume: 0, isMuted: false), for: "z")
        XCTAssertEqual(store.load("z"), AppVolume(volume: 0, isMuted: false))
        XCTAssertEqual(store.load("z").effectiveGain, 0)
        store.save(AppVolume(volume: 0.6, isMuted: true), for: "m")
        XCTAssertEqual(store.load("m").volume, 0.6, accuracy: 1e-6)
        XCTAssertEqual(store.load("m").effectiveGain, 0)
    }

    func testOutOfRangeAndCorruptValuesAreClamped() {
        let store = VolumeStore(defaults: defaults)
        defaults.set(7.0, forKey: "mixer.volume.big")
        defaults.set(-3.0, forKey: "mixer.volume.neg")
        defaults.set("lixo", forKey: "mixer.volume.bad")
        XCTAssertEqual(store.load("big").volume, 4)   // teto de 400%
        XCTAssertEqual(store.load("neg").volume, 0)
        XCTAssertEqual(store.load("bad").volume, 1)
    }
}
