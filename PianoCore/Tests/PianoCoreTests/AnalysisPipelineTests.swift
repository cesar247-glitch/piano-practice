import XCTest
@testable import PianoCore

/// End-to-end: synthetic audio → onsets → accepted note events.
final class AnalysisPipelineTests: XCTestCase {
    private func note(_ midi: Int, sr: Double, amplitude: Double = 0.3) -> [Float] {
        SignalFactory.mix(
            SignalFactory.room(seconds: 1.5, sampleRate: sr),
            SignalFactory.piano(frequency: PitchMath.frequency(midi: midi), start: 0.3, length: 1.2, total: 1.5,
                                sampleRate: sr, amplitude: amplitude))
    }

    func testEachLessonNoteYieldsOneEventWithCorrectMIDI() {
        for sr in SignalFactory.sampleRates {
            for midi in [60, 62, 64, 65, 67] {
                let run = SignalFactory.analyze(note(midi, sr: sr), sampleRate: sr)
                XCTAssertEqual(run.onsets.count, 1, "MIDI \(midi) @ \(sr)")
                XCTAssertEqual(run.accepted.map(\.midi), [midi], "MIDI \(midi) @ \(sr)")
            }
        }
    }

    func testWrongOctaveNotesAreDetectedAsThemselves() {
        // The detector must report C3 and C5 honestly so the matcher can reject them.
        for sr in SignalFactory.sampleRates {
            XCTAssertEqual(SignalFactory.analyze(note(48, sr: sr), sampleRate: sr).accepted.map(\.midi), [48])
            XCTAssertEqual(SignalFactory.analyze(note(72, sr: sr), sampleRate: sr).accepted.map(\.midi), [72])
        }
    }

    func testSoftNote() {
        for sr in SignalFactory.sampleRates {
            let run = SignalFactory.analyze(note(60, sr: sr, amplitude: 0.006), sampleRate: sr)
            XCTAssertEqual(run.accepted.map(\.midi), [60], "soft C4 @ \(sr)")
        }
    }

    func testFeedbackLatencyIsWellUnder250ms() throws {
        for sr in SignalFactory.sampleRates {
            let run = SignalFactory.analyze(note(64, sr: sr), sampleRate: sr)
            let e = try XCTUnwrap(run.accepted.first)
            XCTAssertLessThan(e.detectedTime - e.onsetTime, 0.10)
            XCTAssertEqual(e.onsetTime, 0.3, accuracy: 0.03, "onset should land on the attack")
        }
    }

    func testSingleDecayingAttackProducesExactlyOneEvent() {
        for sr in SignalFactory.sampleRates {
            let signal = SignalFactory.mix(
                SignalFactory.room(seconds: 3, sampleRate: sr),
                SignalFactory.piano(frequency: PitchMath.frequency(midi: 64), start: 0.3, length: 2.7, total: 3,
                                    sampleRate: sr, decay: 1.2))
            let run = SignalFactory.analyze(signal, sampleRate: sr)
            XCTAssertEqual(run.onsets.count, 1)
            XCTAssertEqual(run.accepted.count, 1)
        }
    }

    func testBeatingUnisonStringsDoNotRetrigger() {
        for sr in SignalFactory.sampleRates {
            var parts = [SignalFactory.room(seconds: 4, sampleRate: sr)]
            for detune in [-0.8, 0, 0.9] {
                parts.append(SignalFactory.piano(frequency: 329.63 + detune, start: 0.3, length: 3.6, total: 4,
                                                 sampleRate: sr, amplitude: 0.15, decay: 0.7))
            }
            let signal = parts.dropFirst().reduce(parts[0]) { SignalFactory.mix($0, $1) }
            XCTAssertEqual(SignalFactory.analyze(signal, sampleRate: sr).onsets.count, 1)
        }
    }

    func testSamePitchAttackPairGivesTwoDistinctOnsetIDs() {
        for sr in SignalFactory.sampleRates {
            let f = PitchMath.frequency(midi: 64)
            let signal = SignalFactory.mix(
                SignalFactory.room(seconds: 2, sampleRate: sr),
                SignalFactory.piano(frequency: f, start: 0.3, length: 1.7, total: 2, sampleRate: sr, decay: 0.8),
                SignalFactory.piano(frequency: f, start: 0.7, length: 1.0, total: 2, sampleRate: sr, decay: 0.8))
            let run = SignalFactory.analyze(signal, sampleRate: sr)
            XCTAssertEqual(run.accepted.map(\.midi), [64, 64])
            XCTAssertEqual(Set(run.accepted.map(\.onsetID)).count, 2)
        }
    }

    func testPitchChangeWhilePreviousNoteRings() {
        for sr in SignalFactory.sampleRates {
            let signal = SignalFactory.mix(
                SignalFactory.room(seconds: 2, sampleRate: sr),
                SignalFactory.piano(frequency: PitchMath.frequency(midi: 60), start: 0.3, length: 1.7, total: 2, sampleRate: sr),
                SignalFactory.piano(frequency: PitchMath.frequency(midi: 62), start: 0.8, length: 1.0, total: 2, sampleRate: sr))
            XCTAssertEqual(SignalFactory.analyze(signal, sampleRate: sr).accepted.map(\.midi), [60, 62])
        }
    }

    func testSilenceProducesNothing() {
        for sr in SignalFactory.sampleRates {
            let run = SignalFactory.analyze(SignalFactory.silence(seconds: 1.5, sampleRate: sr), sampleRate: sr)
            XCTAssertTrue(run.onsets.isEmpty)
            XCTAssertTrue(run.accepted.isEmpty)
        }
    }

    func testNoiseIsRejected() {
        for sr in SignalFactory.sampleRates {
            var signal = SignalFactory.room(seconds: 1.5, sampleRate: sr)
            let burst = SignalFactory.noise(seconds: 1.0, sampleRate: sr, amplitude: 0.05, seed: 9)
            for i in burst.indices { signal[Int(0.5 * sr) + i] += burst[i] }
            let run = SignalFactory.analyze(signal, sampleRate: sr)
            XCTAssertTrue(run.accepted.isEmpty, "noise must never become a note event")
        }
    }

    func testCentsToleranceBoundaryAfterCalibration() {
        let sr = 48_000.0
        // 30¢ sharp of E4: accepted as E4.
        let ok = SignalFactory.mix(SignalFactory.room(seconds: 1.5, sampleRate: sr),
                                   SignalFactory.piano(frequency: PitchMath.frequency(midi: 64) * pow(2, 30.0 / 1200),
                                                       start: 0.3, length: 1.2, total: 1.5, sampleRate: sr, inharmonicity: 0))
        XCTAssertEqual(SignalFactory.analyze(ok, sampleRate: sr).accepted.map(\.midi), [64])
        // 46¢ sharp: outside ±40¢, rejected rather than guessed.
        let off = SignalFactory.mix(SignalFactory.room(seconds: 1.5, sampleRate: sr),
                                    SignalFactory.piano(frequency: PitchMath.frequency(midi: 64) * pow(2, 46.0 / 1200),
                                                        start: 0.3, length: 1.2, total: 1.5, sampleRate: sr, inharmonicity: 0))
        let run = SignalFactory.analyze(off, sampleRate: sr)
        XCTAssertTrue(run.accepted.isEmpty)
        XCTAssertEqual(run.results.count, 1)
        // The same 46¢-sharp piano reads in tune once A4 is calibrated 46¢ sharp.
        let calibrated = SignalFactory.analyze(off, sampleRate: sr, a4: PitchMath.a4(forOffsetCents: 46))
        XCTAssertEqual(calibrated.accepted.map(\.midi), [64])
    }

    func testResetClearsState() {
        let sr = 44_100.0
        let pipeline = AnalysisPipeline(sampleRate: sr)
        _ = pipeline.process(note(60, sr: sr))
        pipeline.reset()
        XCTAssertFalse(pipeline.tracker.isAwaitingPitch)
        let frames = pipeline.process(SignalFactory.silence(seconds: 0.5, sampleRate: sr))
        XCTAssertTrue(frames.allSatisfy { $0.onset == nil && $0.results.isEmpty })
    }
}
