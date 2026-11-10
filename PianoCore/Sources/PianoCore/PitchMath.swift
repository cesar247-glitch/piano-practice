import Foundation

/// MIDI / frequency conversions. MIDI 60 = C4 (middle C), MIDI 69 = A4.
public enum PitchMath {
    public static let defaultA4: Double = 440.0

    /// Continuous MIDI value: 69 + 12 × log2(f / A4).
    public static func midiValue(frequency: Double, a4: Double = defaultA4) -> Double {
        69.0 + 12.0 * log2(frequency / a4)
    }

    /// Nearest MIDI note: round(69 + 12 × log2(f / A4)).
    public static func nearestMIDI(frequency: Double, a4: Double = defaultA4) -> Int {
        Int(midiValue(frequency: frequency, a4: a4).rounded())
    }

    public static func frequency(midi: Int, a4: Double = defaultA4) -> Double {
        a4 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// Cents of `frequency` relative to the equal-tempered `midi` note.
    public static func cents(frequency: Double, relativeTo midi: Int, a4: Double = defaultA4) -> Double {
        1200.0 * log2(frequency / self.frequency(midi: midi, a4: a4))
    }

    /// Reference A4 for a fixed tuning offset in cents (e.g. -20 → 434.9 Hz).
    public static func a4(forOffsetCents cents: Double) -> Double {
        defaultA4 * pow(2.0, cents / 1200.0)
    }

    public static func offsetCents(forA4 a4: Double) -> Double {
        1200.0 * log2(a4 / defaultA4)
    }

    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Scientific pitch name, e.g. 60 → "C4", 61 → "C♯4", 48 → "C3".
    public static func name(midi: Int) -> String {
        let pitchClass = ((midi % 12) + 12) % 12
        let octave = Int(floor(Double(midi) / 12.0)) - 1
        return "\(sharpNames[pitchClass])\(octave)"
    }

    public static func isBlackKey(midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
    }
}
