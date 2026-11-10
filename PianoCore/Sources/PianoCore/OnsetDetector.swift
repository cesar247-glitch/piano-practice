import Foundation

/// A single detected strike. Every strike gets a unique, monotonically increasing ID,
/// and downstream consumers may use each ID at most once.
public struct OnsetEvent: Equatable, Sendable {
    public let id: UInt64
    /// Time of the hop in which the attack was detected (seconds, same base as the pipeline).
    public let time: Double
    public let levelDB: Double

    public init(id: UInt64, time: Double, levelDB: Double) {
        self.id = id
        self.time = time
        self.levelDB = levelDB
    }
}

public struct OnsetConfiguration: Equatable, Sendable {
    /// Absolute gate: hops quieter than this never start a note.
    public var minLevelDB: Double = -58
    /// The attack must be at least this far above the (adaptive or calibrated) noise floor.
    public var aboveFloorDB: Double = 12
    /// Attack test: rise versus the minimum of the previous `riseLookbackHops` hops.
    public var riseDB: Double = 6
    public var riseLookbackHops: Int = 3
    /// Rearm once the envelope has stopped rising: `hopsBelowPeakToRearm` consecutive hops
    /// at least `belowPeakDB` under the post-attack peak, or any drop of `rearmDropDB`.
    public var belowPeakDB: Double = 1
    public var hopsBelowPeakToRearm: Int = 3
    public var rearmDropDB: Double = 4
    /// Short guard against double-triggering on one attack. Deliberately not a long debounce.
    public var minInterOnsetSeconds: Double = 0.08
    /// How fast the adaptive floor may creep upward (dB per second). It falls quickly.
    public var floorRiseDBPerSecond: Double = 3

    public init() {}
}

/// Energy-envelope onset detector with an adaptive floor and hysteresis.
///
/// A decaying tone never rises, so it cannot produce a second onset. A new strike of the
/// same pitch produces a fresh rise and therefore a fresh onset ID.
public final class OnsetDetector {
    public var configuration: OnsetConfiguration
    public let hopDuration: Double

    /// Optional floor from the quiet-room calibration. The effective floor never drops below it.
    public var calibratedFloorDB: Double?

    public private(set) var adaptiveFloorDB: Double = -90
    public private(set) var isArmed = true

    private var history: [Double] = []
    private var peakSinceOnset: Double = -200
    private var hopsBelowPeak = 0
    private var lastOnsetTime = -Double.infinity
    private var nextID: UInt64

    public init(hopDuration: Double, configuration: OnsetConfiguration = .init(), firstID: UInt64 = 1) {
        self.hopDuration = hopDuration
        self.configuration = configuration
        self.nextID = firstID
    }

    public var effectiveFloorDB: Double {
        max(adaptiveFloorDB, calibratedFloorDB ?? -200)
    }

    public func reset() {
        history.removeAll()
        isArmed = true
        peakSinceOnset = -200
        hopsBelowPeak = 0
        lastOnsetTime = -Double.infinity
        adaptiveFloorDB = -90
    }

    /// Feed one hop's RMS level. Returns an onset if this hop is a new attack.
    public func process(levelDB: Double, time: Double) -> OnsetEvent? {
        let c = configuration
        let recentMin = history.min() ?? -200
        let floor = effectiveFloorDB

        // Hysteresis: rearm only after the previous attack has peaked and started to fall.
        if !isArmed {
            if levelDB > peakSinceOnset {
                peakSinceOnset = levelDB
                hopsBelowPeak = 0
            } else if levelDB < peakSinceOnset - c.belowPeakDB {
                hopsBelowPeak += 1
            } else {
                hopsBelowPeak = 0
            }
            if hopsBelowPeak >= c.hopsBelowPeakToRearm
                || levelDB <= peakSinceOnset - c.rearmDropDB
                || levelDB < floor + c.aboveFloorDB * 0.5 {
                isArmed = true
            }
        }

        var onset: OnsetEvent?
        if isArmed,
           levelDB >= c.minLevelDB,
           levelDB >= floor + c.aboveFloorDB,
           levelDB - recentMin >= c.riseDB,
           time - lastOnsetTime >= c.minInterOnsetSeconds {
            onset = OnsetEvent(id: nextID, time: time, levelDB: levelDB)
            nextID &+= 1
            isArmed = false
            peakSinceOnset = levelDB
            hopsBelowPeak = 0
            lastOnsetTime = time
        }

        // Adaptive floor: falls fast, creeps up slowly only while nothing is sounding.
        if levelDB < adaptiveFloorDB {
            adaptiveFloorDB += (levelDB - adaptiveFloorDB) * 0.5
        } else if onset == nil && isArmed && levelDB < floor + c.aboveFloorDB {
            adaptiveFloorDB += min(levelDB - adaptiveFloorDB, c.floorRiseDBPerSecond * hopDuration)
        }

        history.append(levelDB)
        if history.count > c.riseLookbackHops { history.removeFirst(history.count - c.riseLookbackHops) }
        return onset
    }
}
