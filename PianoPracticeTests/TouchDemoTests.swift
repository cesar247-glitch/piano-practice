import XCTest
@testable import PianoPractice

/// App-level wiring: Touch Demo drives the same lesson logic and timing as the microphone.
/// (A simulator pass validates wiring and game flow only, not acoustic input.)
@MainActor
final class TouchDemoTests: XCTestCase {
    private func lesson(_ id: String) throws -> Lesson {
        try XCTUnwrap(LessonLibrary.bundled().first { $0.id == id })
    }

    func testTouchDemoCompletesKeyCheck() throws {
        let clock = ManualClock(now: 50)
        let model = PracticeViewModel(lesson: try lesson("key-check"), mode: .touchDemo, clock: clock)

        model.touch(midi: 62) // wrong note first
        XCTAssertEqual(model.engine.targetIndex, 0)
        XCTAssertEqual(model.wrongAttempts, 1)

        for note in model.engine.notes {
            XCTAssertEqual(model.engine.targetIndex, note.index)
            model.touch(midi: note.midi)
            guard case .holding = model.engine.phase else { return XCTFail("tap should start the hold cue") }
            // A second tap during the cue must not skip ahead.
            model.touch(midi: note.midi)
            clock.advance(by: model.engine.duration(of: note))
            model.tick()
        }
        XCTAssertTrue(model.engine.isFinished)
        XCTAssertEqual(model.engine.progressCount, 8)
        XCTAssertNotNil(model.finishedAfter)

        model.restart()
        XCTAssertEqual(model.engine.targetIndex, 0)
        XCTAssertNil(model.finishedAfter)
        XCTAssertEqual(model.wrongAttempts, 0)
    }

    func testEachTapIsAFreshOnset() throws {
        let clock = ManualClock(now: 0)
        let model = PracticeViewModel(lesson: try lesson("key-check"), mode: .touchDemo, clock: clock)
        for midi in [60, 62, 64, 65, 67] {
            model.touch(midi: midi)
            clock.advance(by: 1)
            model.tick()
        }
        // Two consecutive E4 taps advance two separate targets.
        model.touch(midi: 64)
        clock.advance(by: 0.5)
        model.tick()
        XCTAssertEqual(model.engine.targetIndex, 6)
        model.touch(midi: 64)
        guard case .holding(6, _, _) = model.engine.phase else { return XCTFail("second E4 tap should match index 6") }
    }

    func testMicrophoneModeIgnoresTaps() throws {
        let model = PracticeViewModel(lesson: try lesson("key-check"), mode: .microphone, clock: ManualClock())
        model.touch(midi: 60)
        XCTAssertTrue(model.engine.isWaiting)
        XCTAssertEqual(model.engine.targetIndex, 0)
    }

    func testTempoAndLoopControls() throws {
        let clock = ManualClock(now: 0)
        let model = PracticeViewModel(lesson: try lesson("ode-to-joy"), mode: .touchDemo, clock: clock)
        model.setTempoScale(0.6)
        XCTAssertEqual(model.engine.duration(of: model.engine.notes[0]), 0.75 / 0.6, accuracy: 1e-9)
        model.toggleLoop()
        XCTAssertTrue(model.isLooping)
        XCTAssertEqual(model.engine.loopRange, 0...3)
        model.toggleLoop()
        XCTAssertFalse(model.isLooping)
    }
}
