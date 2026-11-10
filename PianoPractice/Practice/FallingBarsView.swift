import PianoCore
import SwiftUI

/// Note bars above the strike line. Uses the same `KeyboardGeometry` as the keyboard, so each
/// bar is centered on its key. Bar length = score duration. Bars freeze while the lesson
/// waits for a strike and move toward the line during the hold cue; the struck bar is
/// consumed at the line as the cue runs.
struct FallingBarsView: View {
    let geometry: KeyboardGeometry
    let model: PracticeViewModel
    /// How many beats of music fit between the top of the view and the strike line.
    var beatsVisible: Double = 4

    var body: some View {
        let moving = model.engine.holdProgress(at: model.clock.now) != nil
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moving)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, now: model.clock.now)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        let engine = model.engine
        let lineY = size.height
        let ppb = size.height / beatsVisible
        let clockBeat = engine.clockBeat(at: now)
        let firstIndex = engine.targetIndex ?? engine.notes.count

        // Faint beat grid that moves with the music.
        let firstGrid = ceil(clockBeat)
        var beat = firstGrid
        while beat <= clockBeat + beatsVisible {
            let y = lineY - (beat - clockBeat) * ppb
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Theme.hairline.opacity(0.35)), lineWidth: 0.5)
            beat += 1
        }

        for note in engine.notes where note.index >= firstIndex {
            guard let key = geometry.key(for: note.midi) else { continue }
            let bottom = lineY - (note.startBeat - clockBeat) * ppb
            let top = bottom - note.beats * ppb
            if top > lineY { continue }
            if bottom < 0 { break }
            let visibleTop = max(0, top + 1.5)
            let visibleBottom = min(lineY, bottom - 1.5)
            guard visibleBottom > visibleTop else { continue }

            let isTarget = note.index == engine.targetIndex
            let width = (key.isBlack ? geometry.blackKeyWidth : geometry.whiteKeyWidth) * 0.72
            let rect = CGRect(x: key.centerX - width / 2, y: visibleTop, width: width, height: visibleBottom - visibleTop)
            let path = Path(roundedRect: rect, cornerRadius: min(7, width / 3), style: .continuous)

            if isTarget {
                context.fill(path, with: .color(Theme.brass))
            } else {
                context.fill(path, with: .color(Theme.upcoming.opacity(0.42)))
                context.stroke(path, with: .color(Theme.upcoming.opacity(0.7)), lineWidth: 1)
            }

            if rect.height > 22 {
                let label = Text(note.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isTarget ? Theme.ebony : Theme.ivory.opacity(0.9))
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - 11))
            }
        }
    }
}

/// The obvious strike line where the target bar settles.
struct StrikeLine: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.brass.opacity(0.25)).frame(height: 8).blur(radius: 4)
            Rectangle().fill(Theme.brass).frame(height: 2)
        }
        .frame(height: 8)
        .allowsHitTesting(false)
    }
}

/// Visual duration cue: fills over the score duration after a matching strike. It is a timer,
/// not a measurement of how long the key was actually held.
struct HoldCueView: View {
    let model: PracticeViewModel
    var compact = false

    var body: some View {
        let engine = model.engine
        let holding = engine.holdProgress(at: model.clock.now) != nil
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !holding)) { _ in
            let progress = model.engine.holdProgress(at: model.clock.now)
            HStack(spacing: 10) {
                if let target = engine.target {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress == nil ? "Play" : "Hold")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(target.name)
                            .font(Theme.title(compact ? 22 : 28))
                            .foregroundStyle(progress == nil ? Theme.brass : Theme.ivory)
                    }
                    .frame(minWidth: compact ? 54 : 64, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.hairline.opacity(0.5))
                                Capsule().fill(Theme.brass)
                                    .frame(width: proxy.size.width * (progress ?? 0))
                            }
                        }
                        .frame(height: 8)
                        Text(beatsLabel(target.beats))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(width: compact ? 110 : 130)
                }
            }
        }
    }

    private func beatsLabel(_ beats: Double) -> String {
        let value = beats == beats.rounded() ? String(Int(beats)) : String(format: "%.1f", beats)
        return "\(value) beat\(beats == 1 ? "" : "s")"
    }
}
