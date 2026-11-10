import Foundation

/// Quiet-room noise calibration: listen for a couple of seconds and take a high
/// percentile of the hop levels as the noise floor.
public struct NoiseFloorCalibrator: Sendable {
    public let duration: Double
    public let percentile: Double
    private var levels: [Double] = []
    private var startTime: Double?

    public init(duration: Double = 2.0, percentile: Double = 0.9) {
        self.duration = duration
        self.percentile = percentile
    }

    public var progress: Double {
        guard let startTime, let last = lastTime else { return 0 }
        return min(1, (last - startTime) / duration)
    }

    private var lastTime: Double?

    public var isComplete: Bool { progress >= 1 }

    public mutating func add(levelDB: Double, time: Double) {
        if startTime == nil { startTime = time }
        lastTime = time
        levels.append(levelDB)
    }

    /// The measured floor in dBFS, available once complete.
    public var floorDB: Double? {
        guard isComplete, !levels.isEmpty else { return nil }
        let sorted = levels.sorted()
        let idx = min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))
        return sorted[idx]
    }
}

/// Explicit reference-note tuning calibration: the player plays A4 and only a confident
/// estimate close to A4 is accepted. Tuning is never learned from arbitrary lesson notes.
public struct ReferenceA4Calibrator: Sendable {
    public enum Status: Equatable, Sendable {
        case collecting(progress: Double)
        case accepted(a4: Double, offsetCents: Double)
        case rejected(reason: String)
    }

    public let requiredFrames: Int
    public let minConfidence: Double
    /// Accept only if the measured A4 is within this many cents of 440 Hz.
    public let toleranceCents: Double

    private var collected: [Double] = []
    private var offTarget: [Double] = []
    public private(set) var status: Status = .collecting(progress: 0)

    public init(requiredFrames: Int = 20, minConfidence: Double = 0.9, toleranceCents: Double = 50) {
        self.requiredFrames = requiredFrames
        self.minConfidence = minConfidence
        self.toleranceCents = toleranceCents
    }

    @discardableResult
    public mutating func add(_ estimate: PitchEstimate?) -> Status {
        guard case .collecting = status else { return status }
        guard let estimate, estimate.confidence >= minConfidence else { return status }

        let centsFrom440 = PitchMath.cents(frequency: estimate.frequency, relativeTo: 69)
        if abs(centsFrom440) <= 100 {
            collected.append(estimate.frequency)
        } else {
            offTarget.append(estimate.frequency)
            if offTarget.count >= requiredFrames {
                let heard = PitchMath.name(midi: PitchMath.nearestMIDI(frequency: median(offTarget)))
                status = .rejected(reason: "Heard \(heard), not A4. Play the A above middle C and try again.")
                return status
            }
        }

        if collected.count >= requiredFrames {
            let f = median(collected)
            let cents = PitchMath.cents(frequency: f, relativeTo: 69)
            if abs(cents) <= toleranceCents {
                status = .accepted(a4: f, offsetCents: cents)
            } else {
                status = .rejected(reason: String(format: "A4 measured %.1f Hz (%+.0f¢). That is too far from 440 Hz to trust; check you played A4.", f, cents))
            }
        } else {
            status = .collecting(progress: Double(collected.count) / Double(requiredFrames))
        }
        return status
    }

    private func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        return s[s.count / 2]
    }
}
