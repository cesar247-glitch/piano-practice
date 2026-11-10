import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// One raw pitch estimate for one analysis window. Raw estimates are never
/// "note events"; see `NoteEventTracker` for how they become accepted notes.
public struct PitchEstimate: Equatable, Sendable {
    /// Estimated fundamental frequency in Hz.
    public let frequency: Double
    /// 1 − (cumulative mean normalized difference at the chosen lag), clamped to 0…1.
    /// Clean periodic tones are close to 1; noise is well below 0.7.
    public let confidence: Double
    /// RMS level of the analysis window in dBFS.
    public let levelDB: Double

    public init(frequency: Double, confidence: Double, levelDB: Double) {
        self.frequency = frequency
        self.confidence = confidence
        self.levelDB = levelDB
    }
}

public struct YINConfiguration: Equatable, Sendable {
    /// Search range. 120–900 Hz covers C3 (130.8 Hz) through C5 (523 Hz) and beyond,
    /// so octave-error checks are in range and the detector does not depend on the
    /// lesson's C4–G4 targets.
    public var minFrequency: Double
    public var maxFrequency: Double
    /// Absolute threshold for the "first credible minimum" step.
    public var threshold: Double

    public init(minFrequency: Double = 120, maxFrequency: Double = 900, threshold: Double = 0.15) {
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.threshold = threshold
    }
}

/// Monophonic YIN estimator (de Cheveigné & Kawahara, 2002):
/// difference function → cumulative mean normalized difference (CMND) →
/// first minimum under an absolute threshold → parabolic interpolation.
///
/// Pure function of its input window; it knows nothing about lesson targets.
public final class YINPitchEstimator {
    public let sampleRate: Double
    public let windowSize: Int
    public let configuration: YINConfiguration

    public let tauMin: Int
    public let tauMax: Int
    /// Integration length W. W + tauMax + 1 ≤ windowSize.
    public let integrationLength: Int

    private var difference: [Double]
    private var cmnd: [Double]
    private var squarePrefix: [Double]
    private var scratch: [Float]

    public init(sampleRate: Double, windowSize: Int = 2048, configuration: YINConfiguration = .init()) {
        precondition(sampleRate > 0, "sample rate must be positive")
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.configuration = configuration
        let tMin = max(2, Int(floor(sampleRate / configuration.maxFrequency)))
        let tMax = Int(ceil(sampleRate / configuration.minFrequency)) + 1
        precondition(tMax * 2 < windowSize, "window too short for the minimum frequency")
        tauMin = tMin
        tauMax = tMax
        integrationLength = windowSize - tMax - 1
        difference = Array(repeating: 0, count: tMax + 1)
        cmnd = Array(repeating: 1, count: tMax + 1)
        squarePrefix = Array(repeating: 0, count: windowSize + 1)
        scratch = Array(repeating: 0, count: windowSize)
    }

    public func estimate(_ samples: [Float]) -> PitchEstimate? {
        samples.withUnsafeBufferPointer { estimate($0) }
    }

    /// Analyzes the most recent `windowSize` samples of `samples`.
    /// Returns nil for digital silence or too-short input.
    public func estimate(_ samples: UnsafeBufferPointer<Float>) -> PitchEstimate? {
        guard samples.count >= windowSize, let base = samples.baseAddress else { return nil }
        let start = samples.count - windowSize

        // Copy and remove DC so the energy terms are well-behaved.
        var mean: Double = 0
        for i in 0..<windowSize { mean += Double(base[start + i]) }
        mean /= Double(windowSize)
        var energy: Double = 0
        for i in 0..<windowSize {
            let v = Float(Double(base[start + i]) - mean)
            scratch[i] = v
            energy += Double(v) * Double(v)
        }
        let rms = sqrt(energy / Double(windowSize))
        guard rms > 1e-7 else { return nil }
        let levelDB = 20 * log10(rms)

        // Prefix sums of squares for the energy terms of d(τ).
        squarePrefix[0] = 0
        for i in 0..<windowSize {
            squarePrefix[i + 1] = squarePrefix[i] + Double(scratch[i]) * Double(scratch[i])
        }

        let w = integrationLength
        let e0 = squarePrefix[w] - squarePrefix[0]

        // d(τ) = Σ (x[j] − x[j+τ])² = E(0..W) + E(τ..τ+W) − 2·Σ x[j]x[j+τ]
        difference[0] = 0
        scratch.withUnsafeBufferPointer { buf in
            let p = buf.baseAddress!
            for tau in 1...tauMax {
                let eTau = squarePrefix[tau + w] - squarePrefix[tau]
                let cross = Self.dot(p, p + tau, count: w)
                difference[tau] = max(0, e0 + eTau - 2 * cross)
            }
        }

        // Cumulative mean normalized difference.
        cmnd[0] = 1
        var running: Double = 0
        for tau in 1...tauMax {
            running += difference[tau]
            cmnd[tau] = running > 0 ? difference[tau] * Double(tau) / running : 1
        }

        // First credible minimum below the absolute threshold, else the global minimum.
        var chosen = -1
        var tau = tauMin
        while tau < tauMax {
            if cmnd[tau] < configuration.threshold {
                while tau + 1 < tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                chosen = tau
                break
            }
            tau += 1
        }
        if chosen < 0 {
            var best = tauMin
            for t in tauMin..<tauMax where cmnd[t] < cmnd[best] { best = t }
            chosen = best
        }

        // Parabolic interpolation around the chosen lag.
        var refined = Double(chosen)
        if chosen > 1 && chosen < tauMax {
            let s0 = cmnd[chosen - 1], s1 = cmnd[chosen], s2 = cmnd[chosen + 1]
            let denom = s0 - 2 * s1 + s2
            if abs(denom) > 1e-12 {
                let shift = 0.5 * (s0 - s2) / denom
                if abs(shift) <= 1 { refined += shift }
            }
        }

        let confidence = min(1, max(0, 1 - cmnd[chosen]))
        return PitchEstimate(frequency: sampleRate / refined, confidence: confidence, levelDB: levelDB)
    }

    @inline(__always)
    private static func dot(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, count: Int) -> Double {
        #if canImport(Accelerate)
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(count))
        return Double(result)
        #else
        var sum: Double = 0
        for i in 0..<count { sum += Double(a[i]) * Double(b[i]) }
        return sum
        #endif
    }
}
