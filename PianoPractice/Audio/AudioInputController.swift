import AVFoundation
import Foundation
import PianoCore

/// Owns the AVAudioSession / AVAudioEngine lifecycle and the input tap.
///
/// Threading:
/// - The tap callback only copies `frameLength` samples into an owned array and enqueues it
///   (bounded) on a serial analysis queue. No framework pointer outlives the callback and
///   no UI work happens there.
/// - Analysis runs on `analysisQueue`. Results are delivered on the main queue, tagged with
///   the session generation. Stopping bumps the generation, so anything still queued from an
///   old session is discarded.
/// - Public methods are called from the main thread.
final class AudioInputController {
    enum StartError: LocalizedError {
        case sessionFailed(String)
        case noInputAvailable
        case invalidInputFormat(sampleRate: Double, channels: UInt32)
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case let .sessionFailed(m): return "Couldn't set up the audio session: \(m)"
            case .noInputAvailable: return "No microphone input is available. Disconnect other audio accessories and try again."
            case let .invalidInputFormat(sr, ch):
                return "The microphone reported an unusable format (\(Int(sr)) Hz, \(ch) channels). Try again, or restart the phone if this persists."
            case let .engineFailed(m): return "Couldn't start listening: \(m)"
            }
        }
    }

    struct Batch {
        let generation: UInt64
        let frames: [AnalysisFrame]
        let droppedBuffers: Int
    }

    /// Main queue.
    var onBatch: ((Batch) -> Void)?
    /// Main queue. Called when the system stopped us (interruption, route change, reset).
    var onStoppedBySystem: ((String) -> Void)?

    private(set) var isRunning = false
    private(set) var sampleRate: Double = 0

    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []

    private let analysisQueue = DispatchQueue(label: "PianoPractice.analysis", qos: .userInteractive)
    private let lock = NSLock()
    private var generationLocked: UInt64 = 0
    private var pendingBuffers = 0
    private var droppedBuffers = 0
    private let maxPendingBuffers = 16
    private let clock: MonotonicClock

    // Accessed only on analysisQueue.
    private var pipeline: AnalysisPipeline?
    private var originSet = false

    init(clock: MonotonicClock = SystemMonotonicClock()) {
        self.clock = clock
    }

    deinit {
        // No weak-self captures here (forming a weak reference during deinit traps).
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        if isRunning { deactivateSession() }
    }

    private var currentGeneration: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generationLocked
    }

    @discardableResult
    private func bumpGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generationLocked &+= 1
        pendingBuffers = 0
        droppedBuffers = 0
        return generationLocked
    }

    // MARK: - Start / stop

    @discardableResult
    func start(a4: Double, noiseFloorDB: Double?) throws -> UInt64 {
        stop() // never stack taps across repeated Start/Stop

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            throw StartError.sessionFailed(error.localizedDescription)
        }
        guard session.isInputAvailable else {
            deactivateSession()
            throw StartError.noInputAvailable
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            deactivateSession()
            throw StartError.invalidInputFormat(sampleRate: format.sampleRate, channels: format.channelCount)
        }

        let generation = bumpGeneration()
        let rate = format.sampleRate
        let pipeline = AnalysisPipeline(sampleRate: rate, a4: a4)
        pipeline.calibratedNoiseFloorDB = noiseFloorDB
        analysisQueue.sync {
            self.pipeline = pipeline
            self.originSet = false
        }

        // Requested size is a hint; handleTap always reads the actual frameLength.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            self?.handleTap(buffer: buffer, when: when, generation: generation)
        }
        tapInstalled = true
        self.engine = engine

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw StartError.engineFailed(error.localizedDescription)
        }

        sampleRate = rate
        isRunning = true
        addObservers(for: engine)
        return generation
    }

    func stop() {
        bumpGeneration()
        removeObservers()
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        engine = nil
        tapInstalled = false
        if isRunning { deactivateSession() }
        isRunning = false
        analysisQueue.async { [weak self] in
            self?.pipeline = nil
        }
    }

    /// Applies new calibration values to the running pipeline.
    func update(a4: Double, noiseFloorDB: Double?) {
        analysisQueue.async { [weak self] in
            self?.pipeline?.a4 = a4
            self?.pipeline?.calibratedNoiseFloorDB = noiseFloorDB
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Tap (audio thread)

    private func handleTap(buffer: AVAudioPCMBuffer, when: AVAudioTime, generation: UInt64) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }

        lock.lock()
        guard generation == generationLocked else { lock.unlock(); return }
        if pendingBuffers >= maxPendingBuffers {
            droppedBuffers += 1
            lock.unlock()
            return
        }
        pendingBuffers += 1
        lock.unlock()

        // Copy into owned memory; mix down to mono.
        var mono = [Float](repeating: 0, count: frameCount)
        mono.withUnsafeMutableBufferPointer { dst in
            let out = dst.baseAddress!
            if channelCount == 1 {
                out.update(from: channels[0], count: frameCount)
            } else {
                let scale = 1 / Float(channelCount)
                for c in 0..<channelCount {
                    let src = channels[c]
                    for i in 0..<frameCount { out[i] += src[i] * scale }
                }
            }
        }
        let hostSeconds: Double? = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : nil
        let samples = mono // immutable copy for the queue

        analysisQueue.async { [weak self] in
            self?.analyze(samples, hostSeconds: hostSeconds, generation: generation)
        }
    }

    // MARK: - Analysis (analysisQueue)

    private func analyze(_ samples: [Float], hostSeconds: Double?, generation: UInt64) {
        lock.lock()
        let stale = generation != generationLocked
        if !stale { pendingBuffers = max(0, pendingBuffers - 1) }
        let dropped = droppedBuffers
        lock.unlock()
        guard !stale, let pipeline else { return }

        if !originSet {
            // Stream time 0 = first sample of the first buffer, on the monotonic clock base.
            pipeline.timeOrigin = hostSeconds ?? (clock.now - Double(samples.count) / pipeline.sampleRate)
            originSet = true
        }
        let frames = pipeline.process(samples)
        guard !frames.isEmpty else { return }
        let batch = Batch(generation: generation, frames: frames, droppedBuffers: dropped)
        DispatchQueue.main.async { [weak self] in
            guard let self, batch.generation == self.currentGeneration else { return }
            self.onBatch?(batch)
        }
    }

    // MARK: - System events

    private func addObservers(for engine: AVAudioEngine) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self?.stopBySystem("Listening was interrupted (call, Siri, alarm or another app). Tap Restart Listening.")
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            switch reason {
            case .oldDeviceUnavailable, .newDeviceAvailable:
                self?.stopBySystem("The audio input changed (headset or AirPods connected or removed). Tap Restart Listening.")
            default:
                break
            }
        })

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: .main) { [weak self] _ in
            self?.stopBySystem("The microphone configuration changed. Tap Restart Listening.")
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: session, queue: .main) { [weak self] _ in
            self?.stopBySystem("iOS reset its audio services. Tap Restart Listening.")
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func stopBySystem(_ message: String) {
        guard isRunning else { return }
        stop()
        onStoppedBySystem?(message)
    }
}
