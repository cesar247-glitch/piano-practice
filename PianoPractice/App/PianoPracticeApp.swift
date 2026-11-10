import SwiftUI

@main
struct PianoPracticeApp: App {
    @State private var settings: AppSettings
    @State private var session: ListeningSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _session = State(initialValue: ListeningSession(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Theme.brass)
        }
        .onChange(of: scenePhase) { _, phase in
            // Release the microphone whenever the app leaves the foreground.
            if phase == .background { session.pauseForBackground() }
        }
    }
}
