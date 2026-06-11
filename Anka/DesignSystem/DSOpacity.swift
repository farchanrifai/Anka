import CoreFoundation

// MARK: - Opacity tokens
//
// Centralizes the recurring alpha values used for tinted fills and pressed
// states so they stay consistent across components (category bubbles, soft
// accent fills, de-emphasized chart slices, custom-button press dim).

enum DSOpacity {
    /// Tinted category bubbles and soft accent fills. (was `.opacity(0.15)`)
    static let subtle: Double = 0.15

    /// De-emphasized / unselected elements such as dimmed chart slices and
    /// scrim overlays. (was `.opacity(0.35)`)
    static let muted: Double = 0.35

    /// Pressed-state dim for custom-drawn buttons. (was `.opacity(0.85)`)
    static let pressed: Double = 0.85
}
