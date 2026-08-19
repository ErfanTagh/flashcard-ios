import SwiftUI
import UIKit

extension Color {
    /// Builds a colour from CSS-style HSL, so the tokens below can be written
    /// with the exact numbers that appear in the web app's `index.css` instead
    /// of hand-converted hex. SwiftUI's own initialiser takes HSB, which is a
    /// different model and would shift every value.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Color {
        let s = saturation / 100
        let l = lightness / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hp = hue.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        let rgb: (Double, Double, Double)
        switch hp {
        case ..<1: rgb = (c, x, 0)
        case ..<2: rgb = (x, c, 0)
        case ..<3: rgb = (0, c, x)
        case ..<4: rgb = (0, x, c)
        case ..<5: rgb = (x, 0, c)
        default:   rgb = (c, 0, x)
        }
        return Color(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m)
    }

    /// Resolves per appearance, the way the web app's `:root` / `.dark` blocks do.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// The web app's design system, ported.
///
/// Every value here is the same HSL pair from
/// `flashcard-frontend/src/index.css` — the `:root` block for light, the
/// `.dark` block for dark. Keep the two in step; if a token changes on the web,
/// change the same line here.
enum Theme {
    static let background = Color.adaptive(light: .hsl(220, 25, 97), dark: .hsl(220, 20, 10))
    static let foreground = Color.adaptive(light: .hsl(220, 15, 20), dark: .hsl(220, 15, 95))

    static let card = Color.adaptive(light: .hsl(0, 0, 100), dark: .hsl(220, 18, 14))
    static let cardForeground = foreground

    /// The violet the whole product leads with — identical in both appearances.
    static let primary = Color.hsl(262, 83, 58)
    static let primaryForeground = Color.hsl(0, 0, 100)

    static let secondary = Color.adaptive(light: .hsl(210, 100, 92), dark: .hsl(220, 20, 18))

    static let muted = Color.adaptive(light: .hsl(220, 20, 94), dark: .hsl(220, 20, 18))
    static let mutedForeground = Color.adaptive(light: .hsl(220, 10, 45), dark: .hsl(220, 10, 60))

    /// The pink half of the logo gradient, used for emphasis.
    static let accent = Color.hsl(340, 82, 65)
    static let accentForeground = Color.hsl(0, 0, 100)

    static let destructive = Color.adaptive(light: .hsl(0, 84.2, 60.2), dark: .hsl(0, 62.8, 30.6))
    static let border = Color.adaptive(light: .hsl(220, 15, 88), dark: .hsl(220, 15, 25))

    /// Not part of the web palette — there is no "correct answer" token there.
    /// Picked to sit alongside the violet rather than fight it.
    static let success = Color.adaptive(light: .hsl(152, 60, 36), dark: .hsl(152, 55, 48))

    /// `--radius: 0.75rem`.
    static let radius: CGFloat = 12
    static let radiusLarge: CGFloat = 20

    /// The logo gradient, straight from `recallcards-icon.svg`
    /// (#8B5CF6 → #EC4899, corner to corner).
    static let brandGradient = LinearGradient(
        colors: [Color(red: 139/255, green: 92/255, blue: 246/255),
                 Color(red: 236/255, green: 72/255, blue: 153/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandStart = Color(red: 139/255, green: 92/255, blue: 246/255)
    static let brandEnd = Color(red: 236/255, green: 72/255, blue: 153/255)
}

extension View {
    /// Puts the palette's background behind a `List`/`Form`, which otherwise
    /// paints its own grouped-background colour over it.
    func themedScrollBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
}
