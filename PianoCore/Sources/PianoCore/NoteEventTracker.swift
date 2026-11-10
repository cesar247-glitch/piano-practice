import Foundation

/// An accepted note: one onset, paired with a pitch that stabilized shortly after it.
/// This is what the lesson matcher consumes. Raw `PitchEstimate`s never reach it.
public struct NoteEvent: Equatable, Sendable {
    public let onsetID: UInt64
    /// When the attack happened (monotonic seconds once the pipeline has a time origin).
    public let onsetTime: Double
    /// When the pitch stabilized and the event was emitted.
    public let detectedTime: Double
    public let midi: Int
    public let frequency: Double
    public let cents: Double
    public let confidence: Double

    public init(onsetID: UInt64, onsetTime: Double, detectedTime: Double, midi: Int,
                frequency: Double, cents: Double, confidence: Double) {
        self.onsetID = onsetID
        self.onsetTime = onsetTime
        self.detectedTime = detectedTime
        self.midi = midi
        self.frequency = frequency
        self.cents = cents
        self.confidence = confidence
    }

    public var name: String { PitchMath.name(midi: midi) }
}

public enum TrackerResult: Equatable, Sendable {
    case accepted(NoteEvent)
    /// The strike happened but no trustworthy pitch could be paired with it.
    case rejected(onsetID: UInt64, time: Double, reason: String)
}

public struct TrackerConfiguration: Equatable, Sendable {
    /// Estimates below this confidence are ignored.
    public var minConfidence: Double = 0.80
    /// Consecutive estimates that must agree before a pitch is accepted.
    public var stableFrames: Int = 3
    /// Maximum spread (cents) among those consecutive estimates.
    public var stabilityCents: Double = 30
    /// Accept only if the stabilized pitch is within this many cents of the nearest MIDI note.
    public var centsTolerance: Double = 40
    /// Hops to skip right after an onset (the window still contains pre-attack audio).
    public var skipFramesAfterOnset: Int = 2
    /// Bounded association window after the onset.
    public var maxWindowSeconds: Double = 0.20
    /// Estimates from windows quieter than this are ignored.
    public var minLevelDB: Double = -60
    public var minFrequency: Double = 120
    public var maxFrequency: Double = 900

    public init() {}
}

/// Pairs onsets with pitch. Each onset yields at most one result (accepted or rejected).
public final class NoteEventTracker {
    public var configuration: TrackerConfiguration
    public var a4: Double

    private struct Pending {
        let onset: OnsetEvent
        let deadline: Double
        var skip: Int
        var streak: [(midiValue: Double, frequency: Double, confidence: Double)] = []
        var lastFailure = "no pitch detected"
    }

    private var pending: Pending?

    public init(configuration: TrackerConfiguration = .init(), a4: Double = PitchMath.defaultA4) {
        self.configuration = configuration
        self.a4 = a4
    }

    public func reset() { pending = nil }

    public var isAwaitingPitch: Bool { pending != nil }

    public func process(time: Double, estimate: PitchEstimate?, onset: OnsetEvent?) -> [TrackerResult] {
        var results: [TrackerResult] = []
        let c = configuration

        if let onset {
            if let old = pending {
                results.append(.rejected(onsetID: old.onset.id, time: time,
                                         reason: "new strike before pitch settled (\(old.lastFailure))"))
            }
            pending = Pending(onset: onset, deadline: onset.time + c.maxWindowSeconds, skip: c.skipFramesAfterOnset)
        }

        guard var p = pending else { return results }

        if time > p.deadline {
            results.append(.rejected(onsetID: p.onset.id, time: time, reason: p.lastFailure))
            pending = nil
            return results
        }

        if p.skip > 0 {
            p.skip -= 1
            pending = p
            return results
        }

        guard let est = estimate else {
            p.streak.removeAll()
            p.lastFailure = "no pitch detected"
            pending = p
            return results
        }
        if est.levelDB < c.minLevelDB {
            p.streak.removeAll()
            p.lastFailure = String(format: "input too quiet (%.0f dB)", est.levelDB)
            pending = p
            return results
        }
        if est.confidence < c.minConfidence {
            p.streak.removeAll()
            p.lastFailure = String(format: "low confidence (%.2f)", est.confidence)
            pending = p
            return results
        }
        if est.frequency < c.minFrequency * 0.97 || est.frequency > c.maxFrequency * 1.03 {
            p.streak.removeAll()
            p.lastFailure = String(format: "pitch out of range (%.0f Hz)", est.frequency)
            pending = p
            return results
        }

        let m = PitchMath.midiValue(frequency: est.frequency, a4: a4)
        p.streak.append((m, est.frequency, est.confidence))
        if p.streak.count > c.stableFrames { p.streak.removeFirst(p.streak.count - c.stableFrames) }

        guard p.streak.count == c.stableFrames else {
            p.lastFailure = "pitch still settling"
            pending = p
            return results
        }

        let values = p.streak.map { $0.midiValue }
        let spreadCents = ((values.max() ?? 0) - (values.min() ?? 0)) * 100
        guard spreadCents <= c.stabilityCents else {
            p.lastFailure = String(format: "unstable pitch (%.0f¢ spread)", spreadCents)
            pending = p
            return results
        }

        let sorted = p.streak.sorted { $0.midiValue < $1.midiValue }
        let median = sorted[sorted.count / 2]
        let midi = Int(median.midiValue.rounded())
        let cents = (median.midiValue - Double(midi)) * 100
        pending = nil

        if abs(cents) > c.centsTolerance {
            results.append(.rejected(onsetID: p.onset.id, time: time,
                                     reason: "\(PitchMath.name(midi: midi)) is " + String(format: "%+.0f", cents)
                                         + "¢ off — check tuning calibration"))
        } else {
            let confidence = p.streak.map { $0.confidence }.reduce(0, +) / Double(p.streak.count)
            results.append(.accepted(NoteEvent(onsetID: p.onset.id, onsetTime: p.onset.time, detectedTime: time,
                                               midi: midi, frequency: median.frequency, cents: cents,
                                               confidence: confidence)))
        }
        return results
    }
}
