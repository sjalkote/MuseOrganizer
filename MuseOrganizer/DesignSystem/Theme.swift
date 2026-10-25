import SwiftUI
import UIKit

// MARK: - Color tokens
// Warm paper base, near-black ink, one vermilion accent used sparingly (Airbnb-style restraint).
// Muse has its own gradient and appears only where Muse is acting. Views use these tokens, never raw hex.

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

extension Color {
    /// Dynamic color with alpha, for shadows and scrims.
    init(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark).withAlphaComponent(darkAlpha)
                : UIColor(hex: light).withAlphaComponent(lightAlpha)
        })
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
    // Base: warm paper. Cards float on it with a soft shadow instead of sitting in gray boxes.
    static let canvas = Color(light: 0xF6F4F0, dark: 0x0B0B0C)
    static let panel = Color(light: 0xFFFFFF, dark: 0x18181A)
    static let background = Color(light: 0xFFFFFF, dark: 0x0B0B0C)
    static let fill = Color(light: 0xF0EDE8, dark: 0x242426)
    static let fillStrong = Color(light: 0xE3DFD8, dark: 0x323235)
    static let separator = Color(light: 0xECE8E2, dark: 0x2A2A2D)
    static let shadow = Color(light: 0x3A2E20, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0)

    // Ink (warm grays)
    static let ink = Color(light: 0x1D1B18, dark: 0xF4F2EE)
    static let inkSecondary = Color(light: 0x6E6A63, dark: 0xA19D96)
    static let inkFaint = Color(light: 0xB3AEA6, dark: 0x5B5853) // icons and rules only, never body text

    // Primary buttons are ink, like Airbnb and Apple Invites. The accent marks selection and progress.
    static let cta = ink
    static let onCta = Color(light: 0xFFFFFF, dark: 0x111111)
    static let accent = Color(light: 0xC93C22, dark: 0xFF7A5C)
    static let accentFill = Color(light: 0xFBEAE5, dark: 0x3A1C15)
    static let onAccent = Color.white

    // Muse: the agent's own color, never used for anything else.
    static let muse = Color(light: 0xC2335E, dark: 0xFF7DA3)
    static let museGradient = LinearGradient(colors: [Color(hex: 0xFFA544), Color(hex: 0xF0507E)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    // Status (always paired with an icon or words)
    static let positive = Color(light: 0x18794E, dark: 0x4CC38A)
    static let caution = Color(light: 0x9A5B00, dark: 0xF1B44C)
    static let critical = Color(light: 0xC22C2C, dark: 0xFF6B6B)
}

/// Each kind of thing in a plan has its own color, so areas are easy to tell apart while scrolling.
/// Kept muted so the plan cover and Muse carry the color.
struct Tint: Hashable {
    var strong: Color   // icons, labels
    var soft: Color     // tiles, section bands

    static let flights = Tint(strong: Color(light: 0x1F6FD1, dark: 0x6AAEFF), soft: Color(light: 0xE5EFFC, dark: 0x13233A))
    static let stays = Tint(strong: Color(light: 0xB45F06, dark: 0xF4AE55), soft: Color(light: 0xFCEFDF, dark: 0x33230F))
    static let activities = Tint(strong: Color(light: 0x16804A, dark: 0x5AD192), soft: Color(light: 0xE2F4E9, dark: 0x112D1D))
    static let money = Tint(strong: Color(light: 0x7A3FC4, dark: 0xB991FF), soft: Color(light: 0xF0E8FC, dark: 0x251937))
    static let dates = Tint(strong: Color(light: 0xC0306A, dark: 0xFF7EB0), soft: Color(light: 0xFCE7EF, dark: 0x351A26))
    static let car = Tint(strong: Color(light: 0xC2410C, dark: 0xFF9A66), soft: Color(light: 0xFDEBE1, dark: 0x36200F))
    static let neutral = Tint(strong: Color(light: 0x5C5852, dark: 0xB0ACA5), soft: Color(light: 0xF0EDE8, dark: 0x2A2A2D))
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
    static let s: CGFloat = 12
    static let m: CGFloat = 18
    static let l: CGFloat = 26
    static let xl: CGFloat = 32
}

enum Motion {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
}

// MARK: - Type
// New York (serif) for names and big moments, SF for everything you read and tap. All scale with Dynamic Type.

extension Font {
    /// Plan names and greetings: the editorial voice.
    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let title = Font.system(.title2, design: .serif, weight: .semibold)
    /// Small caps-style label above a section ("UP NEXT").
    static let eyebrow = Font.caption.weight(.semibold)
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let heading = Font.title3.weight(.semibold)
    static let bodyRegular = Font.body
    static let bodyStrong = Font.body.weight(.semibold)
    static let small = Font.footnote
    static let smallStrong = Font.footnote.weight(.semibold)
}

extension View {
    /// Big numbers: prices, counts, payments.
    func figure() -> some View { monospacedDigit() }

    /// Uppercase, tracked label that sits above a title.
    func eyebrowStyle(_ color: Color = Palette.inkSecondary) -> some View {
        font(.eyebrow).textCase(.uppercase).tracking(0.8).foregroundStyle(color)
    }

    /// The one shadow cards use: soft and warm, gone in dark mode.
    func cardShadow() -> some View {
        shadow(color: Palette.shadow, radius: 18, x: 0, y: 8)
    }
}

/// Press feedback for tappable rows and cards: a slight sink, like Airbnb's cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
