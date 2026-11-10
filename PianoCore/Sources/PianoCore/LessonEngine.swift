import Foundation

/// Where the lesson is.
public enum PracticePhase: Equatable, Sendable {
    /// Target `index` is at the strike line, armed, and waiting for a fresh matching strike.
    case waiting(index: Int, armedAt: TimeInterval)
    /// Target `index` was struck; a visual hold cue runs for the score duration.
    /// This is a timer cue only — it is not a measurement of how long the key was held.
    case holding(index: Int, startedAt: TimeInterval, duration: TimeInterval)
    case finished(at: TimeInterval)
}

/// Why a strike did or did not advance the lesson. Shown in the debug panel.
public enum MatchOutcome: Equatable, Sendable {
    case accepted(index: Int, midi: Int)
    case wrongNote(expected: Int, heard: Int)
    case duplicateOnset(id: UInt64)
    case onsetBeforeArmed
    case holdInProgress
    case lessonFinished

    public var advanced: Bool {
        if case .accepted = self { return true }
        return false
    }

    public var reason: String {
        switch self {
        case let .accepted(_, midi): return "matched \(PitchMath.name(midi: midi))"
        case let .wrongNote(expected, heard):
            if expected % 12 == heard % 12 {
                return "wrong octave: expected \(PitchMath.name(midi: expected)), heard \(PitchMath.name(midi: heard))"
            }
            return "wrong note: expected \(PitchMath.name(midi: expected)), heard \(PitchMath.name(midi: heard))"
        case .duplicateOnset: return "same strike already used"
        case .onsetBeforeArmed: return "strike began before this target was armed"
        case .holdInProgress: return "hold cue still running; next target not armed yet"
        case .lessonFinished: return "lesson finished"
        }
    }
}

/// Single-note wait-mode lesson logic. Pure value type: time is always passed in, so tests
/// drive it with a controllable clock and a synthetic note-event stream.
///
/// Rules:
/// - Only a `NoteEvent` whose MIDI number (including octave) equals the target advances.
/// - Each onset ID is consumed at most once, and only onsets that start after the target
///   was armed count. A decaying tone from the previous strike can never satisfy the next
///   target, even at the same pitch.
/// - After a match the hold cue runs for the score duration at the current speed; the next
///   target is armed only when that timer ends. Waiting for a strike and the hold timer are
///   separate phases.
public struct LessonEngine: Sendable {
    public let lesson: Lesson
    public let notes: [ScoredNote]

    public private(set) var phase: PracticePhase
    /// 0.6, 0.8 or 1.0 in the UI; any positive value is accepted.
    public private(set) var tempoScale: Double
    public private(set) var loopRange: ClosedRange<Int>?
    public private(set) var loopsCompleted = 0
    public private(set) var lastOutcome: MatchOutcome?
    public private(set) var acceptedCount = 0

    private var consumedOnsets: Set<UInt64> = []

    public init(lesson: Lesson, now: TimeInterval, tempoScale: Double = 1.0) {
        precondition(!lesson.events.isEmpty, "lesson has no notes")
        self.lesson = lesson
        self.notes = lesson.notes
        self.tempoScale = tempoScale
        self.phase = .waiting(index: 0, armedAt: now)
    }

    // MARK: - Derived state

    public var secondsPerBeat: Double { 60.0 / (lesson.tempo * tempoScale) }

    public func duration(of note: ScoredNote) -> TimeInterval { note.beats * secondsPerBeat }

    public var targetIndex: Int? {
        switch phase {
        case let .waiting(i, _): return i
        case let .holding(i, _, _): return i
        case .finished: return nil
        }
    }

    public var target: ScoredNote? { targetIndex.map { notes[$0] } }

    public var isWaiting: Bool { if case .waiting = phase { return true } else { return false } }
    public var isFinished: Bool { if case .finished = phase { return true } else { return false } }

    /// Notes completed in this pass: a struck note counts as completed.
    public var progressCount: Int {
        switch phase {
        case let .waiting(i, _): return i
        case let .holding(i, _, _): return i + 1
        case .finished: return notes.count
        }
    }

    /// Hold-cue fill 0…1 while holding, nil otherwise.
    public func holdProgress(at now: TimeInterval) -> Double? {
        guard case let .holding(_, start, duration) = phase else { return nil }
        return min(1, max(0, (now - start) / duration))
    }

    /// Lesson clock in beats. Frozen at the target's start while waiting; advances during holds.
    public func clockBeat(at now: TimeInterval) -> Double {
        switch phase {
        case let .waiting(i, _):
            return notes[i].startBeat
        case let .holding(i, _, _):
            return notes[i].startBeat + notes[i].beats * (holdProgress(at: now) ?? 0)
        case .finished:
            return lesson.totalBeats
        }
    }

    // MARK: - Mutations

    /// Advances timers. Returns true if the phase changed.
    @discardableResult
    public mutating func tick(now: TimeInterval) -> Bool {
        guard case let .holding(index, start, duration) = phase else { return false }
        let end = start + duration
        guard now >= end else { return false }

        if let loop = loopRange, index == loop.upperBound {
            loopsCompleted += 1
            phase = .waiting(index: loop.lowerBound, armedAt: end)
        } else if index + 1 < notes.count {
            phase = .waiting(index: index + 1, armedAt: end)
        } else {
            phase = .finished(at: end)
        }
        return true
    }

    /// Offers one accepted note event to the lesson.
    @discardableResult
    public mutating func handle(_ event: NoteEvent, now: TimeInterval) -> MatchOutcome {
        tick(now: now)

        let outcome: MatchOutcome
        if consumedOnsets.contains(event.onsetID) {
            outcome = .duplicateOnset(id: event.onsetID)
        } else {
            consumedOnsets.insert(event.onsetID)
            switch phase {
            case .finished:
                outcome = .lessonFinished
            case .holding:
                outcome = .holdInProgress
            case let .waiting(index, armedAt):
                let expected = notes[index].midi
                if event.onsetTime < armedAt {
                    outcome = .onsetBeforeArmed
                } else if event.midi != expected {
                    outcome = .wrongNote(expected: expected, heard: event.midi)
                } else {
                    outcome = .accepted(index: index, midi: event.midi)
                    acceptedCount += 1
                    phase = .holding(index: index, startedAt: now, duration: duration(of: notes[index]))
                }
            }
        }
        lastOutcome = outcome
        return outcome
    }

    public mutating func restart(now: TimeInterval) {
        phase = .waiting(index: loopRange?.lowerBound ?? 0, armedAt: now)
        loopsCompleted = 0
        lastOutcome = nil
        consumedOnsets.removeAll()
    }

    /// Applies to the next hold cue; a running cue keeps its duration.
    public mutating func setTempoScale(_ scale: Double) {
        precondition(scale > 0)
        tempoScale = scale
    }

    /// Sets (or clears) a looped section and jumps to its start.
    public mutating func setLoop(_ range: ClosedRange<Int>?, now: TimeInterval) {
        if let range {
            let lo = max(0, min(range.lowerBound, notes.count - 1))
            let hi = max(lo, min(range.upperBound, notes.count - 1))
            loopRange = lo...hi
        } else {
            loopRange = nil
        }
        restart(now: now)
    }
}
