import SwiftUI
import UIKit

// MARK: - Color tokens
// 60% base · 30% ink · 10% indigo. Views use these tokens, never raw hex.

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    // Base. Screens sit on `canvas`; each area of a screen is a `panel` on top of it.
    static let canvas = Color(light: 0xF0F0F3, dark: 0x000000)
    static let panel = Color(light: 0xFFFFFF, dark: 0x1A1A1D)
    static let background = Color(light: 0xFFFFFF, dark: 0x000000)
    static let fill = Color(light: 0xF4F4F6, dark: 0x26262A)
    static let fillStrong = Color(light: 0xE6E6EA, dark: 0x323237)
    static let separator = Color(light: 0xE4E4E8, dark: 0x303035)

    // Ink
    static let ink = Color(light: 0x111113, dark: 0xF5F5F7)
    static let inkSecondary = Color(light: 0x66666E, dark: 0x9C9CA4)
    static let inkFaint = Color(light: 0xA3A3AA, dark: 0x5E5E65) // icons and rules only, never body text

    // Accent: the Planner and the one primary action per screen
    static let accent = Color(light: 0x4F46E5, dark: 0x8C87FF)
    static let accentFill = Color(light: 0xEEEDFC, dark: 0x1D1B3A)
    static let onAccent = Color.white

    // Status (always paired with an icon or words)
    static let positive = Color(light: 0x18794E, dark: 0x4CC38A)
    static let caution = Color(light: 0x9A5B00, dark: 0xF1B44C)
    static let critical = Color(light: 0xC22C2C, dark: 0xFF6B6B)
}

/// Each kind of thing in a plan has its own color, so areas are easy to tell apart while scrolling.
/// Indigo stays reserved for the Planner and primary actions.
struct Tint: Hashable {
    var strong: Color   // icons, labels
    var soft: Color     // tiles, section bands

    static let flights = Tint(strong: Color(light: 0x1F6FD1, dark: 0x6AAEFF), soft: Color(light: 0xE5EFFC, dark: 0x13233A))
    static let stays = Tint(strong: Color(light: 0xB45F06, dark: 0xF4AE55), soft: Color(light: 0xFCEFDF, dark: 0x33230F))
    static let activities = Tint(strong: Color(light: 0x16804A, dark: 0x5AD192), soft: Color(light: 0xE2F4E9, dark: 0x112D1D))
    static let money = Tint(strong: Color(light: 0x7A3FC4, dark: 0xB991FF), soft: Color(light: 0xF0E8FC, dark: 0x251937))
    static let dates = Tint(strong: Color(light: 0xC0306A, dark: 0xFF7EB0), soft: Color(light: 0xFCE7EF, dark: 0x351A26))
    static let car = Tint(strong: Color(light: 0xC2410C, dark: 0xFF9A66), soft: Color(light: 0xFDEBE1, dark: 0x36200F))
    static let neutral = Tint(strong: Color(light: 0x55555C, dark: 0xB0B0B8), soft: Color(light: 0xEDEDF0, dark: 0x2A2A2E))
    static let planner = Tint(strong: Palette.accent, soft: Palette.accentFill)
}

// MARK: - Spacing (8-pt grid)

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

enum Motion {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
}

// MARK: - Type
// Four sizes (34 / 20 / 17 / 13), two weights (regular / semibold). All scale with Dynamic Type.

extension Font {
    static let hero = Font.largeTitle.weight(.semibold)
    static let heading = Font.title3.weight(.semibold)
    static let bodyRegular = Font.body
    static let bodyStrong = Font.body.weight(.semibold)
    static let small = Font.footnote
    static let smallStrong = Font.footnote.weight(.semibold)
}

extension View {
    /// Big numbers: prices, counts, payments.
    func figure() -> some View { monospacedDigit() }
}

/// Light press feedback for tappable rows and cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
