import Foundation

/// One score event. This build is monophonic and supports notes only; a "rest" (or any
/// other type) fails to decode rather than being silently dropped, because rests are not
/// implemented in the playback logic yet.
public struct LessonEvent: Codable, Hashable, Sendable {
    public let midi: Int
    public let beats: Double

    public init(midi: Int, beats: Double) {
        self.midi = midi
        self.beats = beats
    }

    private enum CodingKeys: String, CodingKey { case type, midi, beats }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "note"
        guard type == "note" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Event type '\(type)' is not supported in this build (notes only).")
        }
        midi = try c.decode(Int.self, forKey: .midi)
        beats = try c.decode(Double.self, forKey: .beats)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("note", forKey: .type)
        try c.encode(midi, forKey: .midi)
        try c.encode(beats, forKey: .beats)
    }
}

public struct Lesson: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    /// Beats per minute at 100% speed.
    public let tempo: Double
    public let events: [LessonEvent]

    public init(id: String, title: String, subtitle: String? = nil, tempo: Double, events: [LessonEvent]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tempo = tempo
        self.events = events
    }

    /// Notes with start beats derived cumulatively from durations.
    public var notes: [ScoredNote] {
        var beat = 0.0
        return events.enumerated().map { index, event in
            defer { beat += event.beats }
            return ScoredNote(index: index, midi: event.midi, startBeat: beat, beats: event.beats)
        }
    }

    public var totalBeats: Double { events.reduce(0) { $0 + $1.beats } }

    public var midiRange: ClosedRange<Int>? {
        guard let lo = events.map(\.midi).min(), let hi = events.map(\.midi).max() else { return nil }
        return lo...hi
    }

    public enum ValidationError: Error, Equatable {
        case empty(String)
        case badTempo(String)
        case badDuration(String, index: Int)
        case badPitch(String, index: Int)
    }

    public func validate() throws {
        guard !events.isEmpty else { throw ValidationError.empty(id) }
        guard tempo > 0 && tempo < 400 else { throw ValidationError.badTempo(id) }
        for (i, e) in events.enumerated() {
            guard e.beats > 0 && e.beats <= 16 else { throw ValidationError.badDuration(id, index: i) }
            guard (21...108).contains(e.midi) else { throw ValidationError.badPitch(id, index: i) }
        }
    }
}

public struct ScoredNote: Hashable, Identifiable, Sendable {
    public let index: Int
    public let midi: Int
    public let startBeat: Double
    public let beats: Double

    public var id: Int { index }
    public var endBeat: Double { startBeat + beats }
    public var name: String { PitchMath.name(midi: midi) }
}

public enum LessonLibrary {
    private struct File: Codable {
        let version: Int
        let lessons: [Lesson]
    }

    public static func load(from data: Data) throws -> [Lesson] {
        let file = try JSONDecoder().decode(File.self, from: data)
        for lesson in file.lessons { try lesson.validate() }
        return file.lessons
    }

    /// The lesson library bundled with PianoCore.
    public static func bundled() throws -> [Lesson] {
        guard let url = Bundle.module.url(forResource: "lessons", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }
}
