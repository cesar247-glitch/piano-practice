import Foundation
import Observation
import PianoCore

/// Persistent user settings. Tuning is a fixed offset in cents from A4 = 440 Hz; it changes
/// only from the slider or the explicit play-A4 calibration, never during a lesson.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let tuningOffset = "tuningOffsetCents"
        static let noiseFloor = "noiseFloorDB"
        static let debugPanel = "showDebugPanel"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var tuningOffsetCents: Double {
        didSet { defaults.set(tuningOffsetCents, forKey: Key.tuningOffset) }
    }

    /// Quiet-room calibration result in dBFS, or nil to use the adaptive floor only.
    var noiseFloorDB: Double? {
        didSet {
            if let noiseFloorDB { defaults.set(noiseFloorDB, forKey: Key.noiseFloor) }
            else { defaults.removeObject(forKey: Key.noiseFloor) }
        }
    }

    var showDebugPanel: Bool {
        didSet { defaults.set(showDebugPanel, forKey: Key.debugPanel) }
    }

    var referenceA4: Double { PitchMath.a4(forOffsetCents: tuningOffsetCents) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tuningOffsetCents = defaults.object(forKey: Key.tuningOffset) as? Double ?? 0
        noiseFloorDB = defaults.object(forKey: Key.noiseFloor) as? Double
        showDebugPanel = defaults.object(forKey: Key.debugPanel) as? Bool ?? true
    }
}
