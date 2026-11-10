import Foundation

/// Output of one analysis hop.
public struct AnalysisFrame: Equatable, Sendable {
    public let time: Double
    /// RMS of this hop's new samples (dBFS). Drives the level meter and the onset detector.
    public let levelDB: Double
    /// Raw pitch estimate for the latest full window (nil until the window is filled or for silence).
    public let estimate: PitchEstimate?
    public let onset: OnsetEvent?
    public let results: [TrackerResult]
}

/// Mono samples in → per-hop frames out. Owns its buffers; holds no framework pointers.
/// Not thread-safe: drive it from one serial queue.
public final class AnalysisPipeline {
    public let sampleRate: Double
    public let windowSize: Int
    public let hopSize: Int

    public let estimator: YINPitchEstimator
    public let onsetDetector: OnsetDetector
    public let tracker: NoteEventTracker

    /// Added to stream time so frame times share a base with the app's monotonic clock.
    public var timeOrigin: Double = 0

    public var a4: Double {
        get { tracker.a4 }
        set { tracker.a4 = newValue }
    }

    public var calibratedNoiseFloorDB: Double? {
        get { onsetDetector.calibratedFloorDB }
        set { onsetDetector.calibratedFloorDB = newValue }
    }

    private var window: [Float]
    private var hop: [Float]
    private var hopFill = 0
    private var hopsProcessed = 0
    private var samplesProcessed: Int = 0

    /// Defaults: ~2048-sample window and 512-sample hop at 44.1/48 kHz, scaled for other rates.
    public init(sampleRate: Double,
                windowSize: Int? = nil,
                hopSize: Int? = nil,
                yin: YINConfiguration = .init(),
                onset: OnsetConfiguration = .init(),
                tracker trackerConfig: TrackerConfiguration = .init(),
                a4: Double = PitchMath.defaultA4) {
        precondition(sampleRate > 0)
        self.sampleRate = sampleRate
        let scale = max(1, Int((sampleRate / 48_000).rounded()))
        let w = windowSize ?? 2048 * scale
        let h = hopSize ?? 512 * scale
        self.windowSize = w
        self.hopSize = h
        estimator = YINPitchEstimator(sampleRate: sampleRate, windowSize: w, configuration: yin)
        onsetDetector = OnsetDetector(hopDuration: Double(h) / sampleRate, configuration: onset)
        var tc = trackerConfig
        tc.minFrequency = yin.minFrequency
        tc.maxFrequency = yin.maxFrequency
        tracker = NoteEventTracker(configuration: tc, a4: a4)
        window = Array(repeating: 0, count: w)
        hop = Array(repeating: 0, count: h)
    }

    public var hopDuration: Double { Double(hopSize) / sampleRate }

    public func reset() {
        for i in window.indices { window[i] = 0 }
        hopFill = 0
        hopsProcessed = 0
        samplesProcessed = 0
        onsetDetector.reset()
        tracker.reset()
    }

    public func process(_ samples: [Float]) -> [AnalysisFrame] {
        samples.withUnsafeBufferPointer { process($0) }
    }

    public func process(_ samples: UnsafeBufferPointer<Float>) -> [AnalysisFrame] {
        var frames: [AnalysisFrame] = []
        var index = 0
        while index < samples.count {
            let take = min(hopSize - hopFill, samples.count - index)
            for i in 0..<take { hop[hopFill + i] = samples[index + i] }
            hopFill += take
            index += take
            if hopFill == hopSize {
                frames.append(processHop())
                hopFill = 0
            }
        }
        return frames
    }

    private func processHop() -> AnalysisFrame {
        // Slide the window and append the new hop.
        window.withUnsafeMutableBufferPointer { w in
            // Forward copy; destination precedes source, so overlap is safe.
            for i in 0..<(windowSize - hopSize) { w[i] = w[i + hopSize] }
        }
        for i in 0..<hopSize { window[windowSize - hopSize + i] = hop[i] }
        hopsProcessed += 1
        samplesProcessed += hopSize

        var energy: Double = 0
        for v in hop { energy += Double(v) * Double(v) }
        let levelDB = 20 * log10(max(sqrt(energy / Double(hopSize)), 1e-9))

        let time = timeOrigin + Double(samplesProcessed) / sampleRate
        let onset = onsetDetector.process(levelDB: levelDB, time: time)
        let windowFilled = hopsProcessed * hopSize >= windowSize
        let estimate = windowFilled ? estimator.estimate(window) : nil
        let results = tracker.process(time: time, estimate: estimate, onset: onset)
        return AnalysisFrame(time: time, levelDB: levelDB, estimate: estimate, onset: onset, results: results)
    }
}
