import PianoCore
import SwiftUI
import UIKit

/// The landscape-first practice screen. Portrait keeps the target and progress usable.
struct PracticeView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model: PracticeViewModel

    private let lowestWhiteKey: Int

    init(lesson: Lesson, mode: PracticeMode) {
        _model = State(initialValue: PracticeViewModel(lesson: lesson, mode: mode))
        lowestWhiteKey = KeyboardGeometry.lowestWhiteKey(covering: lesson.midiRange ?? 60...67, whiteKeyCount: 9)
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 8) {
                    topBar(compact: !landscape)
                    if model.mode == .microphone { ListeningBanner() }
                    if landscape { landscapeBody } else { portraitBody }
                }
                .padding(.horizontal, landscape ? 12 : 16)
                .padding(.vertical, 6)

                if model.engine.isFinished {
                    CompletionCard(model: model, onReplay: { model.restart() }, onDone: { dismiss() })
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    // MARK: - Layouts

    private var landscapeBody: some View {
        GeometryReader { area in
            let keyboardHeight = min(max(area.size.height * 0.36, 90), 150)
            let geometry = KeyboardGeometry(lowestWhiteMIDI: lowestWhiteKey, whiteKeyCount: 9, width: area.size.width)
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    FallingBarsView(geometry: geometry, model: model)
                    StrikeLine().offset(y: 4)
                }
                .overlay(alignment: .topLeading) {
                    HoldCueView(model: model)
                        .padding(10)
                        .panel()
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if model.mode == .microphone && settings.showDebugPanel {
                        DebugPanel(model: model).padding(6)
                    }
                }
                keyboard(geometry)
                    .frame(height: keyboardHeight)
            }
        }
    }

    private var portraitBody: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            HoldCueView(model: model)
                .padding(14)
                .panel()
            if let next = nextNote {
                Text("Next: \(next.name)")
                    .font(Theme.readout(15))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            GeometryReader { area in
                let geometry = KeyboardGeometry(lowestWhiteMIDI: lowestWhiteKey, whiteKeyCount: 9, width: area.size.width)
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        FallingBarsView(geometry: geometry, model: model, beatsVisible: 3)
                        StrikeLine().offset(y: 4)
                    }
                    keyboard(geometry).frame(height: 96)
                }
            }
            .frame(height: 230)
            if model.mode == .microphone && settings.showDebugPanel {
                DebugPanel(model: model)
            }
            Label("Rotate to landscape for the full view", systemImage: "rotate.right")
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func keyboard(_ geometry: KeyboardGeometry) -> some View {
        let wrong: Int? = {
            if case let .some(.wrongNote(_, heard)) = model.engine.lastOutcome { return heard }
            return nil
        }()
        return TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let pressed = model.lastTouch.flatMap { model.clock.now - $0.time < 0.15 ? $0.midi : nil }
            KeyboardView(geometry: geometry,
                         target: model.engine.target?.midi,
                         wrong: wrong,
                         pressed: pressed,
                         onTap: model.mode == .touchDemo ? { model.touch(midi: $0) } : nil)
        }
    }

    private var nextNote: ScoredNote? {
        guard let i = model.engine.targetIndex, i + 1 < model.engine.notes.count else { return nil }
        return model.engine.notes[i + 1]
    }

    // MARK: - Top bar

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 0) {
                Text(model.lesson.title).font(Theme.title(compact ? 17 : 19)).foregroundStyle(Theme.ivory)
                ModeBadge(mode: model.mode)
            }

            Spacer(minLength: 4)

            Text("\(model.engine.progressCount) / \(model.engine.notes.count)")
                .font(Theme.readout(compact ? 15 : 17))
                .foregroundStyle(Theme.ivory)
                .accessibilityLabel("\(model.engine.progressCount) of \(model.engine.notes.count) notes")

            if !compact {
                Picker("Speed", selection: Binding(get: { model.tempoScale }, set: { model.setTempoScale($0) })) {
                    ForEach(PracticeViewModel.tempoOptions, id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button { model.toggleLoop() } label: {
                    Image(systemName: model.isLooping ? "repeat.circle.fill" : "repeat")
                }
                .accessibilityLabel(model.isLooping ? "Stop looping" : "Loop the next \(PracticeViewModel.loopLength) notes")
            } else {
                Menu {
                    Picker("Speed", selection: Binding(get: { model.tempoScale }, set: { model.setTempoScale($0) })) {
                        ForEach(PracticeViewModel.tempoOptions, id: \.self) { Text("\(Int($0 * 100))% speed").tag($0) }
                    }
                    Button(model.isLooping ? "Stop looping" : "Loop next \(PracticeViewModel.loopLength) notes") { model.toggleLoop() }
                } label: { Image(systemName: "slider.horizontal.3") }
            }

            Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                .accessibilityLabel("Restart")

            if model.mode == .microphone {
                Button { settings.showDebugPanel.toggle() } label: {
                    Image(systemName: settings.showDebugPanel ? "ladybug.fill" : "ladybug")
                }
                .accessibilityLabel("Toggle debug panel")
            }
        }
        .font(.system(size: 17, weight: .medium))
        .frame(height: 40)
    }

    // MARK: - Lifecycle

    private func begin() {
        UIApplication.shared.isIdleTimerDisabled = true
        model.startTicking()
        switch model.mode {
        case .microphone:
            let model = self.model
            session.onNoteEvent = { [weak model] event in model?.handle(event) }
            Task { await session.start() }
        case .touchDemo:
            session.stop() // Touch Demo never listens.
        }
    }

    private func end() {
        UIApplication.shared.isIdleTimerDisabled = false
        model.stopTicking()
        if model.mode == .microphone {
            session.onNoteEvent = nil
            session.stop()
        }
    }
}

// MARK: - Pieces

struct ModeBadge: View {
    let mode: PracticeMode
    var body: some View {
        switch mode {
        case .microphone:
            Label("Microphone", systemImage: "mic.fill")
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
        case .touchDemo:
            Label("Touch Demo · mic off", systemImage: "hand.tap.fill")
                .font(Theme.caption).foregroundStyle(Theme.upcoming)
        }
    }
}

/// Shows why listening isn't happening, with the action that fixes it.
struct ListeningBanner: View {
    @Environment(ListeningSession.self) private var session

    var body: some View {
        switch session.state {
        case .listening:
            EmptyView()
        case .idle, .requestingPermission:
            banner(icon: "mic", text: "Starting the microphone…", tint: Theme.secondaryText, action: nil)
        case .denied:
            banner(icon: "mic.slash", text: "Microphone access is off. Turn it on in Settings to practice with your piano.",
                   tint: Theme.warning, action: ("Open Settings", { session.openSystemSettings() }))
        case let .failed(message), let .interrupted(message):
            banner(icon: "exclamationmark.triangle", text: message, tint: Theme.warning,
                   action: ("Restart Listening", { Task { await session.start() } }))
        }
    }

    private func banner(icon: String, text: String, tint: Color, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .panel()
    }
}

/// Target, detected note and the most recent reason a strike didn't advance.
struct DebugPanel: View {
    @Environment(ListeningSession.self) private var session
    let model: PracticeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("Target", model.engine.target?.name ?? "—")
            row("Heard", heardText)
            row("Matcher", model.engine.lastOutcome?.reason ?? "—")
            row("Detector", session.lastTrackerRejection ?? "—")
            row("Level", String(format: "%.0f dB", session.levelDB) + " · strikes \(session.strikeCount)")
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(8)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Theme.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private var heardText: String {
        guard let e = session.lastNoteEvent else { return "—" }
        return String(format: "%@ %+.0f¢ conf %.2f", e.name, e.cents, e.confidence)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(Theme.secondaryText).frame(width: 62, alignment: .leading)
            Text(value).foregroundStyle(Theme.ivory).lineLimit(2)
        }
    }
}

struct CompletionCard: View {
    let model: PracticeViewModel
    let onReplay: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Lesson complete").font(Theme.title(28)).foregroundStyle(Theme.ivory)
                Text(model.lesson.title).font(Theme.readout(15)).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 22) {
                    stat("\(model.engine.notes.count)", "notes")
                    stat("\(model.wrongAttempts)", model.wrongAttempts == 1 ? "wrong attempt" : "wrong attempts")
                    stat(durationText, "time")
                }
                HStack(spacing: 12) {
                    Button("Done", action: onDone).buttonStyle(.bordered)
                    Button("Replay", action: onReplay).buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(24)
            .panel()
        }
    }

    private var durationText: String {
        let s = Int((model.finishedAfter ?? 0).rounded())
        return String(format: "%ld:%02ld", s / 60, s % 60)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.readout(22)).foregroundStyle(Theme.brass)
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}
