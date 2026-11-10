import Foundation
import Observation
import PianoCore

enum PracticeMode: Hashable {
    /// Real acoustic input through the microphone.
    case microphone
    /// On-screen keys drive the same lesson logic. No microphone; not a test of acoustic input.
    case touchDemo
}

/// Drives one lesson run. Both modes feed `NoteEvent`s into the same `LessonEngine`.
@MainActor
@Observable
final class PracticeViewModel {
    static let tempoOptions: [Double] = [0.6, 0.8, 1.0]
    static let loopLength = 4

    let lesson: Lesson
    let mode: PracticeMode
    @ObservationIgnored let clock: MonotonicClock

    private(set) var engine: LessonEngine
    private(set) var wrongAttempts = 0
    private(set) var startedAt: TimeInterval
    private(set) var finishedAfter: TimeInterval?
    /// Last key tapped in Touch Demo (for a brief press highlight).
    private(set) var lastTouch: (midi: Int, time: TimeInterval)?

    @ObservationIgnored private var nextTouchOnsetID: UInt64 = 1 << 62 // separate ID space from the mic
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(lesson: Lesson, mode: PracticeMode, clock: MonotonicClock = SystemMonotonicClock()) {
        self.lesson = lesson
        self.mode = mode
        self.clock = clock
        let now = clock.now
        engine = LessonEngine(lesson: lesson, now: now)
        startedAt = now
    }

    var tempoScale: Double { engine.tempoScale }
    var isLooping: Bool { engine.loopRange != nil }

    // MARK: - Input

    func handle(_ event: NoteEvent) {
        var copy = engine
        let outcome = copy.handle(event, now: clock.now)
        engine = copy
        if case .wrongNote = outcome { wrongAttempts += 1 }
        noteFinishIfNeeded()
    }

    /// Touch Demo: a tap is a fresh strike with a unique onset ID.
    func touch(midi: Int) {
        guard mode == .touchDemo else { return }
        let now = clock.now
        let event = NoteEvent(onsetID: nextTouchOnsetID, onsetTime: now, detectedTime: now, midi: midi,
                              frequency: PitchMath.frequency(midi: midi), cents: 0, confidence: 1)
        nextTouchOnsetID += 1
        lastTouch = (midi, now)
        handle(event)
    }

    // MARK: - Timers

    func tick() {
        var copy = engine
        if copy.tick(now: clock.now) {
            engine = copy
            noteFinishIfNeeded()
        }
    }

    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
    }

    func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Controls

    func restart() {
        var copy = engine
        copy.restart(now: clock.now)
        engine = copy
        wrongAttempts = 0
        startedAt = clock.now
        finishedAfter = nil
    }

    func setTempoScale(_ scale: Double) {
        var copy = engine
        copy.setTempoScale(scale)
        engine = copy
    }

    /// Toggles a short looped section starting at the current target.
    func toggleLoop() {
        var copy = engine
        if copy.loopRange != nil {
            copy.setLoop(nil, now: clock.now)
        } else {
            let start = copy.targetIndex ?? 0
            let end = min(start + Self.loopLength - 1, copy.notes.count - 1)
            copy.setLoop(start...end, now: clock.now)
        }
        engine = copy
        finishedAfter = nil
    }

    private func noteFinishIfNeeded() {
        if case let .finished(at) = engine.phase, finishedAfter == nil {
            finishedAfter = at - startedAt
        }
    }
}
