import SwiftUI

extension Font {
    // Display
    static let dsHero       = Font.system(size: 48, weight: .bold,     design: .default)
    static let dsTitle      = Font.system(size: 34, weight: .bold,     design: .default)

    // Headings
    static let dsHeadline   = Font.system(size: 20, weight: .semibold, design: .default)
    static let dsSubhead    = Font.system(size: 17, weight: .semibold, design: .default)

    // Body
    static let dsBody       = Font.system(size: 16, weight: .regular,  design: .default)
    static let dsBodyMedium = Font.system(size: 16, weight: .medium,   design: .default)

    // Small
    static let dsCaption    = Font.system(size: 13, weight: .regular,  design: .default)
    static let dsBadge      = Font.system(size: 11, weight: .medium,   design: .default)
}
