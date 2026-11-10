import XCTest
@testable import PianoCore

final class LessonLibraryTests: XCTestCase {
    func testBundledLibrary() throws {
        let lessons = try LessonLibrary.bundled()
        XCTAssertEqual(lessons.map(\.id), ["key-check", "ode-to-joy"])
    }

    func testKeyCheck() throws {
        let lesson = try XCTUnwrap(LessonLibrary.bundled().first { $0.id == "key-check" })
        XCTAssertEqual(lesson.tempo, 60)
        XCTAssertEqual(lesson.events.map(\.midi), [60, 62, 64, 65, 67, 64, 64, 60])
        XCTAssertEqual(lesson.events.map(\.beats), [1, 1, 1, 1, 1, 0.5, 0.5, 2])
        XCTAssertEqual(lesson.notes.map(\.startBeat), [0, 1, 2, 3, 4, 5, 5.5, 6])
        XCTAssertEqual(lesson.totalBeats, 8)
        XCTAssertEqual(lesson.midiRange, 60...67)
    }

    func testOdeToJoy() throws {
        let lesson = try XCTUnwrap(LessonLibrary.bundled().first { $0.id == "ode-to-joy" })
        XCTAssertEqual(lesson.tempo, 80)
        XCTAssertEqual(lesson.events.map(\.midi), [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62])
        XCTAssertEqual(lesson.events.map(\.beats), Array(repeating: 1, count: 12) + [1.5, 0.5, 2])
        XCTAssertEqual(lesson.notes.last?.startBeat, 14)
        XCTAssertEqual(lesson.totalBeats, 16)
    }

    func testRestsAreRejectedUntilImplemented() {
        let json = #"{"version":1,"lessons":[{"id":"x","title":"X","tempo":60,"events":[{"type":"rest","beats":1}]}]}"#
        XCTAssertThrowsError(try LessonLibrary.load(from: Data(json.utf8)))
    }

    func testValidation() {
        let bad = #"{"version":1,"lessons":[{"id":"x","title":"X","tempo":60,"events":[{"midi":60,"beats":0}]}]}"#
        XCTAssertThrowsError(try LessonLibrary.load(from: Data(bad.utf8)))
        let empty = #"{"version":1,"lessons":[{"id":"x","title":"X","tempo":60,"events":[]}]}"#
        XCTAssertThrowsError(try LessonLibrary.load(from: Data(empty.utf8)))
    }
}
