import PianoCore
import SwiftUI

/// Draws the keyboard window from the shared `KeyboardGeometry` (white keys first, black keys
/// layered on top). `geometry.width` must equal the view's width.
struct KeyboardView: View {
    let geometry: KeyboardGeometry
    var target: Int?
    /// A recently heard wrong note, tinted briefly.
    var wrong: Int?
    /// A key being pressed in Touch Demo.
    var pressed: Int?
    var onTap: ((Int) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let yFraction = value.location.y / max(1, proxy.size.height)
                    if let midi = geometry.midi(atX: value.location.x, yFraction: yFraction) {
                        onTap?(midi)
                    }
                },
                including: onTap == nil ? .none : .all
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.map { "Keyboard. Target \(PitchMath.name(midi: $0))" } ?? "Keyboard")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let h = size.height
        let blackHeight = h * geometry.blackKeyHeightFraction
        for key in geometry.keys {
            let rect = CGRect(x: key.x, y: 0, width: key.width, height: key.isBlack ? blackHeight : h)
            let radius: CGFloat = key.isBlack ? 4 : 7
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .path(in: key.isBlack ? rect : rect.insetBy(dx: 1, dy: 0))
            context.fill(shape, with: .color(fill(for: key)))
            if !key.isBlack {
                context.stroke(shape, with: .color(Theme.ebony.opacity(0.35)), lineWidth: 0.5)
            }

            let isTarget = key.midi == target
            if isTarget || (key.midi == 60 && !key.isBlack) {
                let label = Text(key.name)
                    .font(.system(size: isTarget ? 15 : 11, weight: isTarget ? .bold : .medium, design: .rounded))
                    .foregroundColor(isTarget ? (key.isBlack ? Theme.ivory : Theme.ebony) : Theme.ebony.opacity(0.45))
                let y = (key.isBlack ? blackHeight : h) - (isTarget ? 16 : 12)
                context.draw(label, at: CGPoint(x: key.centerX, y: y))
            }
        }
    }

    private func fill(for key: KeyboardGeometry.Key) -> Color {
        if key.midi == pressed { return key.isBlack ? Theme.brass.opacity(0.7) : Theme.brass.opacity(0.75) }
        if key.midi == target { return Theme.brass }
        if key.midi == wrong { return Theme.warning.opacity(key.isBlack ? 0.8 : 0.55) }
        return key.isBlack ? Theme.ebony : Theme.ivory
    }
}
