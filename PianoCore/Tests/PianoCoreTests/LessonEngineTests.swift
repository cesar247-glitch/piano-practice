import XCTest
@testable import PianoCore

/// State tests with an injected clock and a synthetic note-event stream.
final class LessonEngineTests: XCTestCase {
    private var clock: ManualClock!
    private var nextOnset: UInt64 = 1
    private var keyCheck: Lesson!
    private var ode: Lesson!

    override func setUpWithError() throws {
        clock = ManualClock(now: 100)
        nextOnset = 1
        let lessons = try LessonLibrary.bundled()
        keyCheck = try XCTUnwrap(lessons.first { $0.id == "key-check" })
        ode = try XCTUnwrap(lessons.first { $0.id == "ode-to-joy" })
    }

    /// A strike that starts now and stabilizes 62.5 ms later (binary-exact times keep
    /// timer-boundary assertions free of floating-point drift).
    private func strike(_ midi: Int, onsetID: UInt64? = nil, onsetAt: Double? = nil) -> NoteEvent {
        let id: UInt64
        if let onsetID {
            id = onsetID
        } else {
            id = nextOnset
            nextOnset += 1
        }
        let t = onsetAt ?? clock.now
        return NoteEvent(onsetID: id, onsetTime: t, detectedTime: t + 0.0625, midi: midi,
                         frequency: PitchMath.frequency(midi: midi), cents: 0, confidence: 0.99)
    }

    private func play(_ engine: inout LessonEngine, _ midi: Int) -> MatchOutcome {
        let e = strike(midi)
        clock.advance(by: 0.0625)
        return engine.handle(e, now: clock.now)
    }

    func testStartsWaitingOnFirstNote() {
        let engine = LessonEngine(lesson: keyCheck, now: clock.now)
        XCTAssertEqual(engine.targetIndex, 0)
        XCTAssertEqual(engine.target?.midi, 60)
        XCTAssertTrue(engine.isWaiting)
        XCTAssertEqual(engine.progressCount, 0)
        XCTAssertEqual(engine.clockBeat(at: clock.now), 0)
    }

    func testSilenceLeavesScoreWaiting() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        for _ in 0..<40 {
            clock.advance(by: 0.125)
            XCTAssertFalse(engine.tick(now: clock.now))
        }
        XCTAssertEqual(engine.phase, .waiting(index: 0, armedAt: 100))
        XCTAssertEqual(engine.clockBeat(at: clock.now), 0, "lesson clock stays frozen while waiting")
    }

    func testWrongNoteLeavesTargetInPlace() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        for _ in 0..<5 {
            let outcome = play(&engine, 62)  // neighbor key
            XCTAssertEqual(outcome, .wrongNote(expected: 60, heard: 62))
            XCTAssertFalse(outcome.advanced)
        }
        XCTAssertEqual(engine.targetIndex, 0)
        XCTAssertTrue(engine.isWaiting)
        XCTAssertEqual(engine.lastOutcome?.reason, "wrong note: expected C4, heard D4")
    }

    func testWrongOctaveIsRejected() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        XCTAssertEqual(play(&engine, 48), .wrongNote(expected: 60, heard: 48))
        XCTAssertEqual(play(&engine, 72), .wrongNote(expected: 60, heard: 72))
        XCTAssertTrue(engine.lastOutcome!.reason.hasPrefix("wrong octave"))
        XCTAssertEqual(engine.targetIndex, 0)
    }

    func testMatchStartsHoldCueThenArmsNextTarget() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        XCTAssertEqual(play(&engine, 60), .accepted(index: 0, midi: 60))
        guard case let .holding(index, _, duration) = engine.phase else { return XCTFail("expected holding") }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(duration, 1.0, accuracy: 1e-9, "1 beat at 60 BPM")
        XCTAssertEqual(engine.progressCount, 1)

        clock.advance(by: 0.5)
        engine.tick(now: clock.now)
        XCTAssertEqual(engine.holdProgress(at: clock.now)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(engine.clockBeat(at: clock.now), 0.5, accuracy: 1e-9)

        clock.advance(by: 0.5)
        XCTAssertTrue(engine.tick(now: clock.now))
        XCTAssertEqual(engine.targetIndex, 1)
        XCTAssertTrue(engine.isWaiting)
        XCTAssertNil(engine.holdProgress(at: clock.now))
    }

    func testStrikeDuringHoldDoesNotAdvance() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        _ = play(&engine, 60)
        clock.advance(by: 0.2)
        XCTAssertEqual(play(&engine, 62), .holdInProgress, "next target is not armed during the hold cue")
        XCTAssertEqual(engine.targetIndex, 0)
    }

    func testSameOnsetIsConsumedOnce() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        let e = strike(60, onsetID: 42)
        XCTAssertEqual(engine.handle(e, now: clock.now), .accepted(index: 0, midi: 60))
        clock.advance(by: 1.0)
        engine.tick(now: clock.now)
        // Pretend the same onset ID arrives again (e.g. delivered twice).
        let replay = NoteEvent(onsetID: 42, onsetTime: clock.now, detectedTime: clock.now, midi: 62,
                               frequency: 293.7, cents: 0, confidence: 1)
        XCTAssertEqual(engine.handle(replay, now: clock.now), .duplicateOnset(id: 42))
        XCTAssertEqual(engine.targetIndex, 1)
    }

    /// The repeated-E4 rule: two equal consecutive pitches require two distinct onsets,
    /// and a strike that began before the next target was armed can never satisfy it.
    func testRepeatedPitchRequiresDistinctOnsetAfterArming() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        for midi in [60, 62, 64, 65, 67] {
            XCTAssertTrue(play(&engine, midi).advanced)
            clock.advance(by: 1.0)
            engine.tick(now: clock.now)
        }
        XCTAssertEqual(engine.targetIndex, 5)
        XCTAssertEqual(engine.target?.midi, 64)

        // First E4 (half beat = 0.5 s at 60 BPM).
        let firstOnset = clock.now
        XCTAssertTrue(play(&engine, 64).advanced)
        XCTAssertEqual(engine.duration(of: engine.target!), 0.5, accuracy: 1e-9)

        // Let it ring past the hold cue: the next E4 is armed, but nothing new was struck.
        clock.advance(by: 2.0)
        engine.tick(now: clock.now)
        XCTAssertEqual(engine.targetIndex, 6)
        XCTAssertTrue(engine.isWaiting)

        // A late-stabilizing report of the first strike's ringing tone cannot count.
        let ringing = strike(64, onsetAt: firstOnset + 0.01)
        XCTAssertEqual(engine.handle(ringing, now: clock.now), .onsetBeforeArmed)
        XCTAssertEqual(engine.targetIndex, 6)

        // A fresh strike advances exactly once.
        XCTAssertTrue(play(&engine, 64).advanced)
        guard case .holding(6, _, _) = engine.phase else { return XCTFail("expected holding on index 6") }
    }

    func testShortAndLongCues() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        let durations = engine.notes.map { engine.duration(of: $0) }
        XCTAssertEqual(durations, [1, 1, 1, 1, 1, 0.5, 0.5, 2])

        // Ode to Joy at 80 BPM: 1.5 beats = 1.125 s, 0.5 = 0.375 s, 2 = 1.5 s.
        let odeEngine = LessonEngine(lesson: ode, now: clock.now)
        let last3 = odeEngine.notes.suffix(3).map { odeEngine.duration(of: $0) }
        XCTAssertEqual(last3[0], 1.125, accuracy: 1e-9)
        XCTAssertEqual(last3[1], 0.375, accuracy: 1e-9)
        XCTAssertEqual(last3[2], 1.5, accuracy: 1e-9)

        // The two-beat final C4 of Key Check holds for 2 s, not less.
        for midi in [60, 62, 64, 65, 67, 64, 64] {
            _ = play(&engine, midi)
            clock.advance(by: 2.0)
            engine.tick(now: clock.now)
        }
        XCTAssertEqual(engine.target?.midi, 60)
        _ = play(&engine, 60)
        clock.advance(by: 1.875)
        engine.tick(now: clock.now)
        XCTAssertFalse(engine.isFinished)
        clock.advance(by: 0.125)
        engine.tick(now: clock.now)
        XCTAssertTrue(engine.isFinished)
    }

    func testTempoScaleLengthensCues() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now, tempoScale: 1)
        engine.setTempoScale(0.6)
        XCTAssertEqual(engine.duration(of: engine.notes[0]), 1 / 0.6, accuracy: 1e-9)
        engine.setTempoScale(0.8)
        XCTAssertEqual(engine.duration(of: engine.notes[7]), 2 / 0.8, accuracy: 1e-9)
    }

    func testRestartWhileHolding() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        _ = play(&engine, 60)
        clock.advance(by: 0.3)
        engine.restart(now: clock.now)
        XCTAssertEqual(engine.phase, .waiting(index: 0, armedAt: clock.now))
        XCTAssertEqual(engine.progressCount, 0)
        XCTAssertNil(engine.lastOutcome)
        clock.advance(by: 5)
        engine.tick(now: clock.now)
        XCTAssertEqual(engine.targetIndex, 0, "the old hold cue must not fire after a reset")
    }

    func testCompletesWholeLesson() {
        for lesson in [keyCheck!, ode!] {
            var engine = LessonEngine(lesson: lesson, now: clock.now)
            for note in engine.notes {
                XCTAssertEqual(engine.targetIndex, note.index)
                XCTAssertTrue(play(&engine, note.midi).advanced)
                clock.advance(by: engine.duration(of: note))
                engine.tick(now: clock.now)
            }
            XCTAssertTrue(engine.isFinished, lesson.title)
            XCTAssertEqual(engine.progressCount, lesson.events.count)
            XCTAssertEqual(engine.clockBeat(at: clock.now), lesson.totalBeats)
            XCTAssertEqual(play(&engine, 60), .lessonFinished)
        }
    }

    func testSectionLoop() {
        var engine = LessonEngine(lesson: keyCheck, now: clock.now)
        engine.setLoop(2...3, now: clock.now)
        XCTAssertEqual(engine.targetIndex, 2)
        for midi in [64, 65] {
            _ = play(&engine, midi)
            clock.advance(by: 1)
            engine.tick(now: clock.now)
        }
        XCTAssertEqual(engine.targetIndex, 2, "loops back to the section start")
        XCTAssertEqual(engine.loopsCompleted, 1)
        engine.setLoop(nil, now: clock.now)
        XCTAssertEqual(engine.targetIndex, 0)
    }
}
