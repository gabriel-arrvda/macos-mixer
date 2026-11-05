import XCTest
@testable import MixerCore

final class SilenceDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testIdleWithoutActiveApps() {
        var detector = SilenceDetector()
        XCTAssertEqual(detector.update(peaks: [], now: t0), .idle)
    }

    func testSilentOnlyAfterThreshold() {
        var detector = SilenceDetector(threshold: 5)
        XCTAssertEqual(detector.update(peaks: [0], now: t0), .pending)
        XCTAssertEqual(detector.update(peaks: [0], now: t0.addingTimeInterval(4.9)), .pending)
        XCTAssertEqual(detector.update(peaks: [0], now: t0.addingTimeInterval(5)), .silent)
    }

    func testOneAppWithSoundPreventsAlarm() {
        var detector = SilenceDetector(threshold: 5)
        _ = detector.update(peaks: [0, 0], now: t0)
        XCTAssertEqual(detector.update(peaks: [0, 0.4], now: t0.addingTimeInterval(10)), .receiving)
    }

    func testSoundResetsTheClock() {
        var detector = SilenceDetector(threshold: 5)
        _ = detector.update(peaks: [0], now: t0)
        _ = detector.update(peaks: [0.5], now: t0.addingTimeInterval(4))
        XCTAssertEqual(detector.update(peaks: [0], now: t0.addingTimeInterval(6)), .pending)
    }

    func testRecoversAfterSilent() {
        var detector = SilenceDetector(threshold: 1)
        _ = detector.update(peaks: [0], now: t0)
        XCTAssertEqual(detector.update(peaks: [0], now: t0.addingTimeInterval(2)), .silent)
        XCTAssertEqual(detector.update(peaks: [0.3], now: t0.addingTimeInterval(3)), .receiving)
    }
}
