import Foundation
@testable import PianoCore

/// Deterministic synthetic test signals.
enum SignalFactory {
    static let sampleRates: [Double] = [44_100, 48_000]

    struct LCG {
        var state: UInt64
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 33) / Double(1 << 31)) * 2 - 1
        }
    }

    static func silence(seconds: Double, sampleRate: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * sampleRate))
    }

    static func noise(seconds: Double, sampleRate: Double, amplitude: Float, seed: UInt64 = 1) -> [Float] {
        var g = LCG(state: seed)
        return (0..<Int(seconds * sampleRate)).map { _ in g.next() * amplitude }
    }

    static func sine(frequency: Double, seconds: Double, sampleRate: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { i in
            amplitude * Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }

    /// Harmonic-rich, decaying, slightly inharmonic piano-like note.
    static func piano(frequency: Double, start: Double, length: Double, total: Double, sampleRate: Double,
                      amplitude: Double = 0.3, decay: Double = 2.5, inharmonicity: Double = 0.0004,
                      harmonics: Int = 8) -> [Float] {
        let n = Int(total * sampleRate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate - start
            guard t >= 0, t < length else { continue }
            let attack = t < 0.004 ? t / 0.004 : 1
            let env = attack * exp(-decay * t)
            var v = 0.0
            for h in 1...harmonics {
                let hd = Double(h)
                let fh = hd * frequency * sqrt(1 + inharmonicity * hd * hd)
                if fh > sampleRate / 2.2 { break }
                v += (1 / pow(hd, 1.1)) * sin(2 * .pi * fh * t) * exp(-0.6 * (hd - 1) * t)
            }
            out[i] = Float(amplitude * v * env / 1.8)
        }
        return out
    }

    static func mix(_ signals: [Float]...) -> [Float] {
        let n = signals.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: n)
        for s in signals { for i in s.indices { out[i] += s[i] } }
        return out
    }

    /// Low room noise so the adaptive floor has something realistic to track.
    static func room(seconds: Double, sampleRate: Double) -> [Float] {
        noise(seconds: seconds, sampleRate: sampleRate, amplitude: 0.0005, seed: 7)
    }

    struct Run {
        var frames: [AnalysisFrame]
        var onsets: [OnsetEvent] { frames.compactMap(\.onset) }
        var results: [TrackerResult] { frames.flatMap(\.results) }
        var accepted: [NoteEvent] {
            results.compactMap { if case let .accepted(e) = $0 { return e } else { return nil } }
        }
    }

    /// Feeds the signal in uneven chunks, like real tap buffers.
    static func analyze(_ signal: [Float], sampleRate: Double, a4: Double = 440) -> Run {
        let pipeline = AnalysisPipeline(sampleRate: sampleRate, a4: a4)
        var frames: [AnalysisFrame] = []
        let chunkSizes = [1024, 941, 4800, 512, 2048]
        var index = 0, k = 0
        while index < signal.count {
            let n = min(chunkSizes[k % chunkSizes.count], signal.count - index)
            frames += pipeline.process(Array(signal[index..<(index + n)]))
            index += n
            k += 1
        }
        return Run(frames: frames)
    }
}
