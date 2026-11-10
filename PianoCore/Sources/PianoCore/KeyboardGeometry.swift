import Foundation

/// One geometry model shared by the on-screen keyboard and the falling bars, so a bar's
/// center is always the center of its key.
public struct KeyboardGeometry: Equatable, Sendable {
    public struct Key: Equatable, Sendable, Identifiable {
        public let midi: Int
        public let isBlack: Bool
        public let x: Double
        public let width: Double
        public var id: Int { midi }
        public var centerX: Double { x + width / 2 }
        public var name: String { PitchMath.name(midi: midi) }
    }

    public let lowestWhiteMIDI: Int
    public let whiteKeyCount: Int
    public let width: Double
    public let whiteKeyWidth: Double
    public let blackKeyWidth: Double
    /// Fraction of keyboard height covered by black keys.
    public let blackKeyHeightFraction: Double = 0.62

    /// White keys first, then black keys, so drawing in order layers black keys on top.
    public let keys: [Key]
    public let whiteMIDIs: [Int]

    public init(lowestWhiteMIDI: Int, whiteKeyCount: Int, width: Double) {
        precondition(!PitchMath.isBlackKey(midi: lowestWhiteMIDI), "window must start on a white key")
        precondition(whiteKeyCount > 0)
        self.lowestWhiteMIDI = lowestWhiteMIDI
        self.whiteKeyCount = whiteKeyCount
        self.width = width
        let ww = width / Double(whiteKeyCount)
        whiteKeyWidth = ww
        blackKeyWidth = ww * 0.6

        var whites: [Int] = []
        var m = lowestWhiteMIDI
        while whites.count < whiteKeyCount {
            if !PitchMath.isBlackKey(midi: m) { whites.append(m) }
            m += 1
        }
        whiteMIDIs = whites

        var result: [Key] = whites.enumerated().map { i, midi in
            Key(midi: midi, isBlack: false, x: Double(i) * ww, width: ww)
        }
        // A black key sits on the boundary between its lower and upper white neighbors.
        for (i, midi) in whites.enumerated() where i + 1 < whites.count {
            let candidate = midi + 1
            if PitchMath.isBlackKey(midi: candidate) && whites[i + 1] == midi + 2 {
                let boundary = Double(i + 1) * ww
                result.append(Key(midi: candidate, isBlack: true, x: boundary - ww * 0.3, width: ww * 0.6))
            }
        }
        keys = result
    }

    public var midiRange: ClosedRange<Int> { lowestWhiteMIDI...(whiteMIDIs.last ?? lowestWhiteMIDI) }

    public func contains(midi: Int) -> Bool { key(for: midi) != nil }

    public func key(for midi: Int) -> Key? { keys.first { $0.midi == midi } }

    public func centerX(midi: Int) -> Double? { key(for: midi)?.centerX }

    /// Hit test: `yFraction` is 0 at the top of the keys and 1 at the bottom.
    public func midi(atX x: Double, yFraction: Double) -> Int? {
        if yFraction <= blackKeyHeightFraction,
           let black = keys.first(where: { $0.isBlack && x >= $0.x && x < $0.x + $0.width }) {
            return black.midi
        }
        return keys.first(where: { !$0.isBlack && x >= $0.x && x < $0.x + $0.width })?.midi
    }

    /// Chooses the lowest white key of a `whiteKeyCount` window that contains `range`, with
    /// its middle white key as close as possible to `preferredCenter` (middle C by default).
    public static func lowestWhiteKey(covering range: ClosedRange<Int>, whiteKeyCount: Int,
                                      preferredCenter: Int = 60) -> Int {
        let allWhites = (21...108).filter { !PitchMath.isBlackKey(midi: $0) }
        var best: (start: Int, distance: Int)?
        for startIndex in allWhites.indices where startIndex + whiteKeyCount <= allWhites.count {
            let window = Array(allWhites[startIndex..<(startIndex + whiteKeyCount)])
            guard window.first! <= range.lowerBound, window.last! >= range.upperBound else { continue }
            let center = window[whiteKeyCount / 2]
            let distance = abs(center - preferredCenter)
            if best == nil || distance < best!.distance { best = (window.first!, distance) }
        }
        if let best { return best.start }
        // Range wider than the window: start at the range's lowest white key.
        return allWhites.first { $0 >= range.lowerBound } ?? 60
    }
}
