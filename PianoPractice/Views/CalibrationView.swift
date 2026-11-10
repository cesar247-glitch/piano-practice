import PianoCore
import SwiftUI

/// Quiet-room noise calibration, fixed tuning offset, and explicit play-A4 calibration.
/// Tuning is never learned from lesson notes.
struct CalibrationView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                listeningRow
            } footer: {
                Text("Calibration listens through the microphone. Nothing is recorded.")
            }

            Section {
                LabeledContent("Noise floor",
                               value: settings.noiseFloorDB.map { String(format: "%.0f dBFS", $0) } ?? "Adaptive")
                if case let .noise(progress) = session.calibration {
                    ProgressView(value: progress) { Text("Measuring — stay quiet") }
                } else {
                    Button("Calibrate in a quiet room (2 s)") {
                        Task {
                            await session.start()
                            session.beginNoiseCalibration()
                        }
                    }
                    if settings.noiseFloorDB != nil {
                        Button("Clear noise calibration", role: .destructive) {
                            settings.noiseFloorDB = nil
                            session.applySettings()
                        }
                    }
                }
            } header: {
                Text("Quiet-room noise")
            } footer: {
                Text("Strikes must rise clearly above this floor. Re-run it if the room gets noisier or quieter.")
            }

            Section {
                LabeledContent("Reference", value: String(format: "A4 = %.1f Hz (%+.0f¢)",
                                                          settings.referenceA4, settings.tuningOffsetCents))
                Slider(value: $settings.tuningOffsetCents, in: -50...50, step: 1) {
                    Text("Tuning offset")
                } minimumValueLabel: { Text("−50¢") } maximumValueLabel: { Text("+50¢") }
                    .onChange(of: settings.tuningOffsetCents) { _, _ in session.applySettings() }

                if case let .referenceA4(progress) = session.calibration {
                    ProgressView(value: progress) { Text("Listening for A4…") }
                    Button("Cancel", role: .cancel) { session.cancelCalibration() }
                } else {
                    Button("Calibrate by playing A4") {
                        Task {
                            await session.start()
                            session.beginReferenceA4Calibration()
                        }
                    }
                    if settings.tuningOffsetCents != 0 {
                        Button("Reset to A4 = 440 Hz") {
                            settings.tuningOffsetCents = 0
                            session.applySettings()
                        }
                    }
                }
            } header: {
                Text("Tuning")
            } footer: {
                Text("Play A4 — the A above middle C — once and let it ring. Only a confident reading within 50¢ of 440 Hz is accepted. Use this if your piano is noticeably sharp or flat.")
            }

            if let message = session.calibrationMessage {
                Section { Text(message).foregroundStyle(Theme.ivory) }
            }

            Section("Practice") {
                Toggle("Show debug panel during practice", isOn: $settings.showDebugPanel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.stop() }
    }

    @ViewBuilder
    private var listeningRow: some View {
        switch session.state {
        case .listening:
            HStack {
                Label("Listening", systemImage: "waveform").foregroundStyle(Theme.ok)
                Spacer()
                Text(String(format: "%.0f dBFS", session.levelDB)).font(Theme.readout(14))
                Button("Stop") { session.stop() }
            }
        case .denied:
            Button("Microphone access is off — Open Settings") { session.openSystemSettings() }
        case let .failed(message), let .interrupted(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.footnote).foregroundStyle(Theme.warning)
                Button("Restart Listening") { Task { await session.start() } }
            }
        case .idle, .requestingPermission:
            Button("Start Listening") { Task { await session.start() } }
        }
    }
}
