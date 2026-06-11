import SwiftUI

/// Shared press feedback for the app's custom capsule/pill buttons.
/// Native bar buttons get highlight feedback from the system; our hand-rolled
/// capsules (period pill, balance switcher, Save, category chips) previously
/// used `.plain` and gave no response until touch-up. This style adds the
/// standard "squish": a quick scale-down + slight dim while pressed, sprung
/// back on release.
///
/// Usage: `.buttonStyle(.pressable)` — drop-in replacement for `.plain` on
/// fully custom-drawn labels.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Default squish (scale 0.94) — pills and chips.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Gentler squish for large surfaces like the full-width Save capsule.
    static var pressableSubtle: PressableButtonStyle { PressableButtonStyle(scale: 0.97) }
}
