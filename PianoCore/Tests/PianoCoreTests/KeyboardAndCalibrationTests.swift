import XCTest
@testable import PianoCore

final class KeyboardGeometryTests: XCTestCase {
    func testWindowForLessonsIsCenteredOnMiddleC() {
        let lowest = KeyboardGeometry.lowestWhiteKey(covering: 60...67, whiteKeyCount: 9)
        XCTAssertEqual(lowest, 53) // F3 … G4, middle key C4
        let g = KeyboardGeometry(lowestWhiteMIDI: lowest, whiteKeyCount: 9, width: 900)
        XCTAssertEqual(g.whiteMIDIs, [53, 55, 57, 59, 60, 62, 64, 65, 67])
        XCTAssertEqual(g.whiteMIDIs[4], 60)
        XCTAssertTrue((60...67).allSatisfy(g.contains(midi:)))
    }

    func testBlackKeysAreLayeredOnBoundaries() throws {
        let g = KeyboardGeometry(lowestWhiteMIDI: 53, whiteKeyCount: 9, width: 900)
        let blacks = g.keys.filter(\.isBlack).map(\.midi)
        XCTAssertEqual(blacks, [54, 56, 58, 61, 63, 66])
        // All white keys come before any black key (draw order).
        let firstBlack = try XCTUnwrap(g.keys.firstIndex { $0.isBlack })
        XCTAssertTrue(g.keys[..<firstBlack].allSatisfy { !$0.isBlack })
        XCTAssertTrue(g.keys[firstBlack...].allSatisfy(\.isBlack))
        // C♯4 straddles the C4/D4 boundary at x = 500.
        XCTAssertEqual(try XCTUnwrap(g.centerX(midi: 61)), 500, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(g.centerX(midi: 60)), 450, accuracy: 1e-9)
    }

    func testHitTesting() {
        let g = KeyboardGeometry(lowestWhiteMIDI: 53, whiteKeyCount: 9, width: 900)
        XCTAssertEqual(g.midi(atX: 498, yFraction: 0.3), 61, "upper half near boundary hits the black key")
        XCTAssertEqual(g.midi(atX: 498, yFraction: 0.9), 60, "lower part hits the white key")
        XCTAssertEqual(g.midi(atX: 450, yFraction: 0.3), 60)
    }
}

final class CalibrationTests: XCTestCase {
    private func estimate(_ f: Double, confidence: Double = 0.98) -> PitchEstimate {
        PitchEstimate(frequency: f, confidence: confidence, levelDB: -20)
    }

    func testAcceptsConfidentA4NearReference() {
        var c = ReferenceA4Calibrator()
        var status = c.status
        for _ in 0..<20 { status = c.add(estimate(442.0)) }
        guard case let .accepted(a4, cents) = status else { return XCTFail("expected accepted, got \(status)") }
        XCTAssertEqual(a4, 442, accuracy: 0.01)
        XCTAssertEqual(cents, 7.85, accuracy: 0.1)
    }

    func testIgnoresUnconfidentEstimates() {
        var c = ReferenceA4Calibrator()
        for _ in 0..<100 { c.add(estimate(440, confidence: 0.5)) }
        XCTAssertEqual(c.status, .collecting(progress: 0))
    }

    func testRejectsOtherNotes() {
        var c = ReferenceA4Calibrator()
        for _ in 0..<20 { c.add(estimate(PitchMath.frequency(midi: 67))) } // G4
        guard case let .rejected(reason) = c.status else { return XCTFail("expected rejection") }
        XCTAssertTrue(reason.contains("G4"))
    }

    func testRejectsA4TooFarOff() {
        var c = ReferenceA4Calibrator()
        for _ in 0..<20 { c.add(estimate(440 * pow(2, 70.0 / 1200))) }
        guard case .rejected = c.status else { return XCTFail("70¢ off must not be accepted") }
    }

    func testNoiseFloor() throws {
        var n = NoiseFloorCalibrator(duration: 1.0)
        for i in 0...100 { n.add(levelDB: i % 20 == 0 ? -50 : -70, time: Double(i) * 0.01) }
        XCTAssertTrue(n.isComplete)
        XCTAssertEqual(try XCTUnwrap(n.floorDB), -70)
    }
}
