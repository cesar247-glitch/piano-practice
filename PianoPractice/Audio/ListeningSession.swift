import AVFoundation
import Foundation
import Observation
import PianoCore
import UIKit

/// Main-actor view model over the microphone. One instance for the whole app, because there
/// is one microphone. Mic Check, Calibration and Practice all read from it.
@MainActor
@Observable
final class ListeningSession {
    enum State: Equatable {
        case idle
        case requestingPermission
        case denied
        case listening
        case failed(String)
        /// Stopped by the system or by backgrounding; offer Restart Listening.
        case interrupted(String)
    }

    enum Calibration: Equatable {
        case none
        case noise(progress: Double)
        case referenceA4(progress: Double)
    }

    private(set) var state: State = .idle
    private(set) var sampleRate: Double = 0

    // Live readings (raw estimates are kept separate from accepted note events).
    private(set) var levelDB: Double = -120
    private(set) var estimate: PitchEstimate?
    private(set) var lastStrikeTime: Double?
    private(set) var strikeCount = 0
    private(set) var lastNoteEvent: NoteEvent?
    private(set) var lastTrackerRejection: String?
    private(set) var droppedBuffers = 0

    private(set) var calibration: Calibration = .none
    private(set) var calibrationMessage: String?

    /// Accepted note events go here (Practice installs a handler).
    @ObservationIgnored var onNoteEvent: ((NoteEvent) -> Void)?

    @ObservationIgnored let clock: MonotonicClock
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let controller: AudioInputController
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var noiseCalibrator: NoiseFloorCalibrator?
    @ObservationIgnored private var a4Calibrator: ReferenceA4Calibrator?
    @ObservationIgnored private var calibrationDeadline: Double = 0

    init(settings: AppSettings, clock: MonotonicClock = SystemMonotonicClock()) {
        self.settings = settings
        self.clock = clock
        self.controller = AudioInputController(clock: clock)
        // The controller always calls these on the main queue.
        controller.onBatch = { [weak self] batch in
            MainActor.assumeIsolated { self?.handle(batch) }
        }
        controller.onStoppedBySystem = { [weak self] message in
            MainActor.assumeIsolated { self?.systemStopped(message) }
        }
    }

    var isListening: Bool { state == .listening }

    var permissionDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    // MARK: - Control

    func start() async {
        switch state {
        case .listening, .requestingPermission: return
        default: break
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            state = .denied
            return
        case .undetermined:
            state = .requestingPermission
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                state = .denied
                return
            }
        @unknown default:
            break
        }

        do {
            generation = try controller.start(a4: settings.referenceA4, noiseFloorDB: settings.noiseFloorDB)
            sampleRate = controller.sampleRate
            resetReadings()
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        controller.stop()
        cancelCalibration()
        resetReadings()
        switch state {
        case .listening, .requestingPermission: state = .idle
        default: break
        }
    }

    /// Called when the app leaves the foreground.
    func pauseForBackground() {
        guard state == .listening else { return }
        controller.stop()
        cancelCalibration()
        resetReadings()
        state = .interrupted("Listening paused while the app was in the background. Tap Restart Listening.")
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Push changed settings to a running pipeline.
    func applySettings() {
        controller.update(a4: settings.referenceA4, noiseFloorDB: settings.noiseFloorDB)
    }

    // MARK: - Calibration

    func beginNoiseCalibration() {
        guard isListening else { return }
        a4Calibrator = nil
        noiseCalibrator = NoiseFloorCalibrator(duration: 2.0)
        calibration = .noise(progress: 0)
        calibrationMessage = "Keep the room quiet…"
    }

    func beginReferenceA4Calibration() {
        guard isListening else { return }
        noiseCalibrator = nil
        a4Calibrator = ReferenceA4Calibrator()
        calibrationDeadline = clock.now + 10
        calibration = .referenceA4(progress: 0)
        calibrationMessage = "Play A4 — the A above middle C — and let it ring."
    }

    func cancelCalibration() {
        noiseCalibrator = nil
        a4Calibrator = nil
        if calibration != .none { calibration = .none }
    }

    // MARK: - Delivery

    private func handle(_ batch: AudioInputController.Batch) {
        guard batch.generation == generation, state == .listening else { return }
        droppedBuffers = batch.droppedBuffers

        var maxLevel = -200.0
        for frame in batch.frames {
            maxLevel = max(maxLevel, frame.levelDB)
            if let e = frame.estimate, e.confidence >= 0.5, e.levelDB > -70 {
                estimate = e
            } else if frame.levelDB < -70 {
                estimate = nil
            }
            if frame.onset != nil {
                lastStrikeTime = clock.now
                strikeCount += 1
            }
            for result in frame.results {
                switch result {
                case let .accepted(event):
                    lastNoteEvent = event
                    onNoteEvent?(event)
                case let .rejected(_, _, reason):
                    lastTrackerRejection = reason
                }
            }
            feedCalibration(frame)
        }
        levelDB = maxLevel
    }

    private func feedCalibration(_ frame: AnalysisFrame) {
        if var noise = noiseCalibrator {
            noise.add(levelDB: frame.levelDB, time: frame.time)
            noiseCalibrator = noise
            calibration = .noise(progress: noise.progress)
            if let floor = noise.floorDB {
                noiseCalibrator = nil
                calibration = .none
                settings.noiseFloorDB = floor
                applySettings()
                calibrationMessage = String(format: "Noise floor set to %.0f dB.", floor)
            }
        }
        if var cal = a4Calibrator {
            let status = cal.add(frame.estimate)
            a4Calibrator = cal
            switch status {
            case let .collecting(progress):
                calibration = .referenceA4(progress: progress)
                if clock.now > calibrationDeadline {
                    a4Calibrator = nil
                    calibration = .none
                    calibrationMessage = "No confident A4 heard. Tuning unchanged — try again in a quieter room."
                }
            case let .accepted(a4, cents):
                a4Calibrator = nil
                calibration = .none
                settings.tuningOffsetCents = cents
                applySettings()
                calibrationMessage = String(format: "Tuned: A4 = %.1f Hz (%+.0f¢).", a4, cents)
            case let .rejected(reason):
                a4Calibrator = nil
                calibration = .none
                calibrationMessage = reason + " Tuning unchanged."
            }
        }
    }

    private func systemStopped(_ message: String) {
        cancelCalibration()
        resetReadings()
        state = .interrupted(message)
    }

    private func resetReadings() {
        levelDB = -120
        estimate = nil
        lastStrikeTime = nil
        lastNoteEvent = nil
        lastTrackerRejection = nil
        droppedBuffers = 0
    }
}
