import PianoCore
import SwiftUI

/// Diagnostic screen: live level, detected note with octave, Hz, cents, confidence, and a
/// strike indicator. This is where the detector is validated on a real piano.
struct MicCheckView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                controlRow
                stateView
                if session.isListening {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { readout; sidePanel }
                        VStack(spacing: 14) { readout; sidePanel }
                    }
                }
                NavigationLink {
                    CalibrationView()
                } label: {
                    Label("Calibration & settings", systemImage: "tuningfork")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .panel()
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Mic Check")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.stop() }
    }

    // MARK: - Controls & states

    private var controlRow: some View {
        HStack {
            if session.isListening {
                Button(role: .destructive) { session.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
            } else {
                Button { Task { await session.start() } } label: {
                    Label("Start Listening", systemImage: "mic.fill").frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.state == .requestingPermission)
            }
            Spacer()
            if session.isListening {
                Text(String(format: "%.0f kHz", session.sampleRate / 1000))
                    .font(Theme.readout(13)).foregroundStyle(Theme.secondaryText)
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var stateView: some View {
        switch session.state {
        case .idle:
            hint("Put the phone on the music stand with the microphone openings clear, keep the room quiet, leave the sustain pedal up, then tap Start Listening.")
        case .requestingPermission:
            hint("Waiting for microphone permission…")
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Label("Microphone access is off", systemImage: "mic.slash.fill")
                    .font(Theme.title(18)).foregroundStyle(Theme.warning)
                Text("Piano Practice needs the microphone to hear your piano. Audio is analyzed on the phone and never recorded or sent anywhere. Open Settings, allow Microphone, then come back.")
                    .font(.system(size: 14)).foregroundStyle(Theme.ivory)
                Button("Open Settings") { session.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).panel()
        case let .failed(message), let .interrupted(message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Not listening", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.title(18)).foregroundStyle(Theme.warning)
                Text(message).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                Button("Restart Listening") { Task { await session.start() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).panel()
        case .listening:
            EmptyView()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).panel()
    }

    // MARK: - Live readout

    private var readout: some View {
        let e = session.estimate
        let a4 = settings.referenceA4
        let midi = e.map { PitchMath.nearestMIDI(frequency: $0.frequency, a4: a4) }
        let cents = e.flatMap { est in midi.map { PitchMath.cents(frequency: est.frequency, relativeTo: $0, a4: a4) } }

        return VStack(spacing: 10) {
            HStack(alignment: .center) {
                StrikeIndicator()
                Spacer()
                Text("strikes \(session.strikeCount)").font(Theme.readout(13)).foregroundStyle(Theme.secondaryText)
            }
            Text(midi.map(PitchMath.name(midi:)) ?? "—")
                .font(.system(size: 88, weight: .semibold, design: .serif))
                .foregroundStyle(confident(e) ? Theme.ivory : Theme.secondaryText.opacity(0.6))
                .minimumScaleFactor(0.5)
                .frame(height: 100)
            HStack(spacing: 18) {
                metric(e.map { String(format: "%.1f", $0.frequency) } ?? "—", "Hz")
                metric(cents.map { String(format: "%+.0f", $0) } ?? "—", "cents")
                metric(e.map { String(format: "%.2f", $0.confidence) } ?? "—", "confidence")
            }
            CentsGauge(cents: cents)
            LevelMeter(levelDB: session.levelDB, floorDB: settings.noiseFloorDB)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .panel()
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accepted note events").font(Theme.caption).foregroundStyle(Theme.secondaryText)
            if let event = session.lastNoteEvent {
                Text(event.name).font(Theme.title(30)).foregroundStyle(Theme.brass)
                Text(String(format: "%+.0f¢ · conf %.2f · %.0f ms after strike",
                            event.cents, event.confidence, (event.detectedTime - event.onsetTime) * 1000))
                    .font(Theme.readout(12)).foregroundStyle(Theme.ivory)
            } else {
                Text("Strike a key").font(Theme.title(20)).foregroundStyle(Theme.secondaryText)
            }
            Divider().overlay(Theme.hairline)
            Text("Last rejected strike").font(Theme.caption).foregroundStyle(Theme.secondaryText)
            Text(session.lastTrackerRejection ?? "—").font(Theme.readout(12)).foregroundStyle(Theme.ivory)
            Divider().overlay(Theme.hairline)
            Text(String(format: "A4 = %.1f Hz · noise floor %@", settings.referenceA4,
                        settings.noiseFloorDB.map { String(format: "%.0f dB", $0) } ?? "adaptive"))
                .font(Theme.readout(12)).foregroundStyle(Theme.secondaryText)
            if session.droppedBuffers > 0 {
                Text("Dropped \(session.droppedBuffers) audio buffers (analysis fell behind)")
                    .font(Theme.caption).foregroundStyle(Theme.warning)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func confident(_ e: PitchEstimate?) -> Bool { (e?.confidence ?? 0) >= 0.8 }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.readout(20)).foregroundStyle(Theme.ivory)
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(minWidth: 70)
    }
}

/// Flashes on every detected onset.
struct StrikeIndicator: View {
    @Environment(ListeningSession.self) private var session

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let age = session.lastStrikeTime.map { session.clock.now - $0 } ?? 10
            let lit = max(0, 1 - age / 0.3)
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.brass.opacity(0.15 + 0.85 * lit))
                    .frame(width: 18, height: 18)
                    .shadow(color: Theme.brass.opacity(lit), radius: 8 * lit)
                Text("STRIKE").font(Theme.caption).foregroundStyle(lit > 0 ? Theme.brass : Theme.secondaryText)
            }
        }
        .accessibilityLabel("Strike indicator")
    }
}

struct LevelMeter: View {
    let levelDB: Double
    let floorDB: Double?
    private let minDB = -80.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let fraction = max(0, min(1, (levelDB - minDB) / -minDB))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.5))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.ok, Theme.brass, Theme.warning], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * fraction)
                    if let floorDB {
                        Rectangle().fill(Theme.ivory.opacity(0.8)).frame(width: 2)
                            .offset(x: proxy.size.width * max(0, min(1, (floorDB - minDB) / -minDB)))
                    }
                }
            }
            .frame(height: 10)
            Text(String(format: "Input level %.0f dBFS", levelDB))
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct CentsGauge: View {
    let cents: Double?

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ForEach([-50.0, -25, 0, 25, 50], id: \.self) { c in
                    Rectangle().fill(c == 0 ? Theme.ivory : Theme.hairline)
                        .frame(width: 1, height: c == 0 ? 14 : 8)
                        .position(x: w / 2 + w / 2 * c / 50, y: 9)
                }
                if let cents {
                    Capsule().fill(abs(cents) <= 40 ? Theme.ok : Theme.warning)
                        .frame(width: 6, height: 16)
                        .position(x: w / 2 + w / 2 * max(-50, min(50, cents)) / 50, y: 9)
                }
            }
        }
        .frame(height: 18)
    }
}
