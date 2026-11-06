import XCTest
@testable import MixerCore

final class VolumeInputTests: XCTestCase {
    func testNumbersWithAndWithoutPercent() {
        XCTAssertEqual(VolumeInput.parse("75", max: 4), .volume(0.75))
        XCTAssertEqual(VolumeInput.parse(" 165% ", max: 4), .volume(1.65))
        XCTAssertEqual(VolumeInput.parse("75,5", max: 4), .volume(0.76))
        XCTAssertEqual(VolumeInput.parse("400", max: 4), .volume(4))
    }

    func testMuteWords() {
        for text in ["m", "M", "mudo", "Mute", "0", "0%"] {
            XCTAssertEqual(VolumeInput.parse(text, max: 4), .mute, text)
        }
    }

    func testInvalidAndAboveMax() {
        for text in ["", "abc", "12a", "-5", "1.2.3", "%"] {
            XCTAssertEqual(VolumeInput.parse(text, max: 4), .invalid, text)
        }
        XCTAssertEqual(VolumeInput.parse("150", max: 1), .invalid)
        XCTAssertEqual(VolumeInput.parse("401", max: 4), .invalid)
    }
}
