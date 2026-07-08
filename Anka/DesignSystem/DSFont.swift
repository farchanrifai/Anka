import SwiftUI
import UIKit

// MARK: - Dynamic-Type-aware font scale
//
// Use these tokens instead of `font(.system(size: X))` so text scales
// with the user's accessibility text-size setting (Settings → Accessibility
// → Display & Text Size → Larger Text).
//
// Every token is anchored to the closest semantic iOS text style via a
// UIFontMetrics-based helper (`relativeTo:`). At the default text size the
// values are identical to the raw sizes they replace; they only differ when
// the user has changed their preferred content size category. (Earlier some
// tokens were declared without `relativeTo:` and so were fixed-size — AC1 in
// the audit; they are all scaled now.)
//
// Usage:
//   Text("Hello").font(.dsBody)         // replaces .system(size: 14)
//   Text("Hello").font(.dsBodyMedium)   // replaces .system(size: 14, weight: .medium)

extension Font {

    /// Internal helper: creates a scalable system font by baking the weight
    /// (and optional design, e.g. `.monospaced`) into a UIFont first, then
    /// scaling it with UIFontMetrics.
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo textStyle: Font.TextStyle) -> Font {
        var uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        if design != .default, let descriptor = uiFont.fontDescriptor.withDesign(design.uiDesign) {
            uiFont = UIFont(descriptor: descriptor, size: size)
        }
        let scaled = UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledFont(for: uiFont)
        return Font(scaled)
    }

    // MARK: Display / Hero (amounts, large numbers)

    /// 52 pt — Today dashboard hero balance amount (UIFontMetrics-scaled).
    static let dsHeroAmount   = Font.system(size: 52, weight: .black, relativeTo: .largeTitle)
    /// 34 pt — section hero numbers.
    static let dsTitle        = Font.system(size: 34, weight: .bold, relativeTo: .title)
    /// 26 pt
    static let dsTitle2       = Font.system(size: 26, relativeTo: .title)
    static let dsTitle2Bold   = Font.system(size: 26, weight: .bold, relativeTo: .title)
    /// 24 pt
    static let dsTitle3       = Font.system(size: 24, relativeTo: .title2)
    /// 24 pt — category emoji in transaction rows. Dynamic-Type-aware
    /// (UIFontMetrics-scaled relative to .title2), unlike the fixed-size `dsTitle3`.
    static let dsEmoji        = Font.system(size: 24, weight: .regular, relativeTo: .title2)

    // MARK: Display Serif (onboarding / editorial headings)

    /// Internal helper: scalable serif system font (New York). Weight is baked
    /// into the UIFont, the serif design is applied via the font descriptor,
    /// then UIFontMetrics scales it — same pattern as `system(size:weight:relativeTo:)`.
    private static func serif(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle) -> Font {
        let base       = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let serifFont  = UIFont(descriptor: descriptor, size: size)
        let scaled     = UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledFont(for: serifFont)
        return Font(scaled)
    }

    /// 40 pt serif — hero display heading (onboarding welcome).
    static let dsSerifHero  = Font.serif(size: 40, weight: .semibold, relativeTo: .largeTitle)
    /// 30 pt serif — page-level display heading (onboarding pages).
    static let dsSerifTitle = Font.serif(size: 30, weight: .semibold, relativeTo: .title)

    // MARK: Body

    /// 20 pt — primary headings
    static let dsHeadline     = Font.system(size: 20, weight: .semibold, relativeTo: .title3)
    static let dsHeadlineSemi = Font.system(size: 17, weight: .semibold, relativeTo: .headline)
    static let dsHeadlineBold = Font.system(size: 17, weight: .bold, relativeTo: .headline)

    /// 17 pt — subheadline
    static let dsSubhead      = Font.system(size: 17, weight: .semibold, relativeTo: .headline)
    static let dsSubheadSemi  = Font.system(size: 15, weight: .semibold, relativeTo: .body)
    static let dsSubheadBold  = Font.system(size: 15, weight: .bold, relativeTo: .body)

    /// 16 pt — body text
    static let dsBody         = Font.system(size: 16, weight: .regular, relativeTo: .body)
    static let dsBodyMedium   = Font.system(size: 16, weight: .medium, relativeTo: .body)
    static let dsBodySemi     = Font.system(size: 14, weight: .semibold, relativeTo: .body)
    static let dsBodyBold     = Font.system(size: 14, weight: .bold, relativeTo: .body)

    // MARK: Small

    /// 13 pt — secondary / supporting text
    static let dsFootnote       = Font.system(size: 13, relativeTo: .callout)
    static let dsFootnoteMedium = Font.system(size: 13, weight: .medium, relativeTo: .callout)
    static let dsFootnoteSemi   = Font.system(size: 13, weight: .semibold, relativeTo: .callout)
    static let dsFootnoteBold   = Font.system(size: 13, weight: .bold, relativeTo: .callout)

    /// 13 pt — captions (legacy alias)
    static let dsCaption        = Font.system(size: 13, weight: .regular, relativeTo: .footnote)
    static let dsCaptionMedium  = Font.system(size: 12, weight: .medium, relativeTo: .callout)
    static let dsCaptionSemi    = Font.system(size: 12, weight: .semibold, relativeTo: .callout)

    /// 11 pt — smallest regular text (chart axis, sub-labels)
    static let dsCaption2       = Font.system(size: 11, relativeTo: .caption)
    static let dsCaption2Semi   = Font.system(size: 11, weight: .semibold, relativeTo: .caption)
    static let dsCaption2Bold   = Font.system(size: 11, weight: .bold, relativeTo: .caption)

    /// 11 pt — badge text
    static let dsBadge          = Font.system(size: 11, weight: .medium, relativeTo: .caption)
    /// 10 pt — badge text (small)
    static let dsBadgeSemi      = Font.system(size: 10, weight: .semibold, relativeTo: .caption)
    static let dsBadgeBold      = Font.system(size: 10, weight: .bold, relativeTo: .caption)
}

// MARK: - Private mapping helpers

private extension Font.Weight {
    /// Maps SwiftUI Font.Weight to the equivalent UIFont.Weight so the weight
    /// can be baked into a UIFont before UIFontMetrics scales it.
    var uiWeight: UIFont.Weight {
        if self == .ultraLight { return .ultraLight }
        if self == .thin       { return .thin       }
        if self == .light      { return .light      }
        if self == .medium     { return .medium     }
        if self == .semibold   { return .semibold   }
        if self == .bold       { return .bold       }
        if self == .heavy      { return .heavy      }
        if self == .black      { return .black      }
        return .regular
    }
}

private extension Font.Design {
    /// Maps SwiftUI Font.Design to UIFontDescriptor.SystemDesign.
    var uiDesign: UIFontDescriptor.SystemDesign {
        if self == .monospaced { return .monospaced }
        if self == .rounded    { return .rounded    }
        if self == .serif      { return .serif      }
        return .default
    }
}

private extension Font.TextStyle {
    /// Maps SwiftUI Font.TextStyle to the UIFont.TextStyle used by UIFontMetrics.
    var uiTextStyle: UIFont.TextStyle {
        if self == .largeTitle  { return .largeTitle   }
        if self == .title       { return .title1       }
        if self == .title2      { return .title2       }
        if self == .title3      { return .title3       }
        if self == .headline    { return .headline     }
        if self == .subheadline { return .subheadline  }
        if self == .callout     { return .callout      }
        if self == .footnote    { return .footnote     }
        if self == .caption     { return .caption1     }
        if self == .caption2    { return .caption2     }
        return .body // covers .body and any future unknown cases
    }
}
