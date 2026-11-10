import PianoCore
import SwiftUI

enum Route: Hashable {
    case micCheck
    case calibration
    case practice(lessonID: String, mode: PracticeMode)
}

struct RootView: View {
    @State private var path: [Route] = []
    private let library: Result<[Lesson], Error> = Result { try LessonLibrary.bundled() }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Route.micCheck) {
                        row(icon: "waveform.badge.mic", title: "Mic Check",
                            detail: "See the note, Hz, cents and confidence the phone hears.")
                    }
                } footer: {
                    Text("Start here on a real piano: confirm C4–G4 read correctly before practicing.")
                }

                switch library {
                case let .success(lessons):
                    Section("Practice with your piano") {
                        ForEach(lessons) { lesson in
                            NavigationLink(value: Route.practice(lessonID: lesson.id, mode: .microphone)) {
                                row(icon: "pianokeys", title: lesson.title, detail: detail(lesson))
                            }
                        }
                    }
                    Section {
                        ForEach(lessons) { lesson in
                            NavigationLink(value: Route.practice(lessonID: lesson.id, mode: .touchDemo)) {
                                row(icon: "hand.tap", title: lesson.title, detail: "Tap the on-screen keys")
                            }
                        }
                    } header: {
                        Text("Touch Demo — microphone off")
                    } footer: {
                        Text("Exercises the same lesson logic and timing with on-screen keys. It does not test acoustic input.")
                    }
                case let .failure(error):
                    Section { Text("Couldn't load lessons: \(error.localizedDescription)").foregroundStyle(Theme.warning) }
                }

                Section {
                    NavigationLink(value: Route.calibration) {
                        row(icon: "tuningfork", title: "Calibration & settings",
                            detail: "Quiet-room noise floor, tuning offset, debug panel")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Piano Practice")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .micCheck:
                    MicCheckView()
                case .calibration:
                    CalibrationView()
                case let .practice(id, mode):
                    if case let .success(lessons) = library, let lesson = lessons.first(where: { $0.id == id }) {
                        PracticeView(lesson: lesson, mode: mode)
                    }
                }
            }
        }
    }

    private func detail(_ lesson: Lesson) -> String {
        "\(lesson.events.count) notes · \(Int(lesson.tempo)) BPM" + (lesson.subtitle.map { " · \($0)" } ?? "")
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.brass)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(18)).foregroundStyle(Theme.ivory)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}
