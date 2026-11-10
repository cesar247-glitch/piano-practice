import XCTest
@testable import PianoCore

final class PitchMathTests: XCTestCase {
    func testMIDINumbering() {
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: 440), 69)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: 261.6256), 60)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: 130.8128), 48)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: 523.2511), 72)
        XCTAssertEqual(PitchMath.frequency(midi: 60), 261.6256, accuracy: 0.001)
        XCTAssertEqual(PitchMath.frequency(midi: 67), 391.9954, accuracy: 0.001)
    }

    func testNames() {
        XCTAssertEqual(PitchMath.name(midi: 60), "C4")
        XCTAssertEqual(PitchMath.name(midi: 61), "C♯4")
        XCTAssertEqual(PitchMath.name(midi: 64), "E4")
        XCTAssertEqual(PitchMath.name(midi: 48), "C3")
        XCTAssertEqual(PitchMath.name(midi: 72), "C5")
        XCTAssertEqual(PitchMath.name(midi: 59), "B3")
        XCTAssertEqual(PitchMath.name(midi: 21), "A0")
    }

    func testRoundingBoundaryAt50Cents() {
        let c4 = PitchMath.frequency(midi: 60)
        let below = c4 * pow(2, 49.9 / 1200)
        let above = c4 * pow(2, 50.1 / 1200)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: below), 60)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: above), 61)
        XCTAssertEqual(PitchMath.cents(frequency: below, relativeTo: 60), 49.9, accuracy: 0.01)
    }

    func testTuningReference() {
        let a4 = PitchMath.a4(forOffsetCents: -30)
        XCTAssertEqual(PitchMath.offsetCents(forA4: a4), -30, accuracy: 1e-9)
        // A piano tuned 30¢ flat: its C4 still reads as C4 with ~0¢ after calibration.
        let flatC4 = PitchMath.frequency(midi: 60, a4: a4)
        XCTAssertEqual(PitchMath.nearestMIDI(frequency: flatC4, a4: a4), 60)
        XCTAssertEqual(PitchMath.cents(frequency: flatC4, relativeTo: 60, a4: a4), 0, accuracy: 1e-6)
        XCTAssertEqual(PitchMath.cents(frequency: flatC4, relativeTo: 60), -30, accuracy: 1e-6)
    }

    func testBlackKeys() {
        XCTAssertEqual((60...71).filter(PitchMath.isBlackKey(midi:)), [61, 63, 66, 68, 70])
    }
}
