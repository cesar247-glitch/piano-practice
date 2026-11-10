import SwiftUI

/// Warm, instrument-panel palette: walnut ground, ivory and ebony keys, brass for the target.
enum Theme {
    static let background = Color(red: 0.086, green: 0.075, blue: 0.063)      // #16130F
    static let panel = Color(red: 0.137, green: 0.118, blue: 0.098)           // #231E19
    static let hairline = Color(red: 0.32, green: 0.28, blue: 0.23)
    static let ivory = Color(red: 0.965, green: 0.937, blue: 0.886)           // #F6EFE2
    static let ivoryShade = Color(red: 0.86, green: 0.83, blue: 0.77)
    static let ebony = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let brass = Color(red: 0.851, green: 0.643, blue: 0.255)           // #D9A441
    static let brassSoft = Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.35)
    static let upcoming = Color(red: 0.62, green: 0.72, blue: 0.70)           // muted verdigris
    static let warning = Color(red: 0.86, green: 0.40, blue: 0.32)
    static let ok = Color(red: 0.55, green: 0.76, blue: 0.52)
    static let secondaryText = Color(red: 0.70, green: 0.66, blue: 0.60)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func readout(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded).monospacedDigit() }
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}
