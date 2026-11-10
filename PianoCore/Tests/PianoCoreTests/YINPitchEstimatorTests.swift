import XCTest
@testable import PianoCore

final class YINPitchEstimatorTests: XCTestCase {
    private let targets: [(name: String, midi: Int)] = [
        ("C3", 48), ("C4", 60), ("D4", 62), ("E4", 64), ("F4", 65), ("G4", 67), ("A4", 69), ("C5", 72),
    ]

    func testCleanSinesAtBothRates() throws {
        for sr in SignalFactory.sampleRates {
            let yin = YINPitchEstimator(sampleRate: sr)
            for t in targets {
                let f = PitchMath.frequency(midi: t.midi)
                let x = SignalFactory.sine(frequency: f, seconds: 0.1, sampleRate: sr)
                let e = try XCTUnwrap(yin.estimate(x), "\(t.name) @ \(sr)")
                XCTAssertEqual(PitchMath.cents(frequency: e.frequency, relativeTo: t.midi), 0, accuracy: 2,
                               "\(t.name) @ \(sr)")
                XCTAssertGreaterThan(e.confidence, 0.95)
            }
        }
    }

    func testHarmonicRichNotesHaveNoOctaveErrors() throws {
        for sr in SignalFactory.sampleRates {
            let yin = YINPitchEstimator(sampleRate: sr)
            for t in targets {
                let x = SignalFactory.piano(frequency: PitchMath.frequency(midi: t.midi), start: 0, length: 0.2,
                                            total: 0.2, sampleRate: sr)
                let e = try XCTUnwrap(yin.estimate(Array(x[2000...])))
                XCTAssertEqual(PitchMath.nearestMIDI(frequency: e.frequency), t.midi, "\(t.name) @ \(sr)")
                XCTAssertLessThan(abs(PitchMath.cents(frequency: e.frequency, relativeTo: t.midi)), 15)
            }
        }
    }

    func testSoftAndDecayedNotes() throws {
        for sr in SignalFactory.sampleRates {
            let yin = YINPitchEstimator(sampleRate: sr)
            let x = SignalFactory.piano(frequency: PitchMath.frequency(midi: 60), start: 0, length: 2,
                                        total: 2, sampleRate: sr, amplitude: 0.01)
            // Late in the decay (≈ −20 dB from the start).
            let late = Array(x[Int(1.0 * sr)..<Int(1.0 * sr) + 2048])
            let e = try XCTUnwrap(yin.estimate(late))
            XCTAssertEqual(PitchMath.nearestMIDI(frequency: e.frequency), 60)
            XCTAssertGreaterThan(e.confidence, 0.8)
        }
    }

    func testSilenceAndNoise() {
        for sr in SignalFactory.sampleRates {
            let yin = YINPitchEstimator(sampleRate: sr)
            XCTAssertNil(yin.estimate(SignalFactory.silence(seconds: 0.05, sampleRate: sr)))
            let n = SignalFactory.noise(seconds: 0.05, sampleRate: sr, amplitude: 0.1, seed: 99)
            if let e = yin.estimate(n) {
                XCTAssertLessThan(e.confidence, 0.5, "white noise must not look periodic")
            }
        }
    }

    func testShortInputReturnsNil() {
        let yin = YINPitchEstimator(sampleRate: 48_000)
        XCTAssertNil(yin.estimate([Float](repeating: 0.1, count: 100)))
    }
}
