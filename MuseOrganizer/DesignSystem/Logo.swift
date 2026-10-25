import SwiftUI

// NxT's logo. Pure SwiftUI with no app dependencies, so scripts/render-icon.swift can render the
// same view into the app icon on a Mac.

private func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// The dusk gradient from the plan covers and Muse's mark: plum at the top, warming to amber.
struct NxTBackground: View {
    var dark = false

    private var colors: [Color] {
        dark
            ? [0x150E24, 0x24153A, 0x1A1530, 0x6E2E4E, 0x9A3F5C, 0x5A2A52, 0xB8603E, 0xC9704A, 0xA8485E].map(hex)
            : [0x2B1E46, 0x4A2A5E, 0x2E2756, 0xC4506F, 0xEC7377, 0xA34A86, 0xFFA544, 0xFFB98A, 0xF2678A].map(hex)
    }

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.58, 0.48], [1, 0.42],
            [0, 1], [0.45, 1], [1, 1],
        ], colors: colors)
    }
}

/// "NxT" in New York: a confident N and T around a lighter italic x.
struct NxTWordmark: View {
    var size: CGFloat
    var color: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.015) {
            Text("N").font(.system(size: size, weight: .semibold, design: .serif))
            Text("x").font(.system(size: size * 0.74, weight: .regular, design: .serif).italic())
                .opacity(0.82)
            Text("T").font(.system(size: size, weight: .semibold, design: .serif))
        }
        .foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NxT")
    }
}

/// The app mark. `rounded` is false for the app icon itself, because iOS rounds that.
struct NxTMark: View {
    enum Style { case standard, dark, tinted }

    var size: CGFloat = 96
    var style: Style = .standard
    var rounded = true

    var body: some View {
        ZStack {
            switch style {
            case .standard: NxTBackground()
            case .dark: NxTBackground(dark: true)
            case .tinted: Color.black
            }
            // A soft glow behind the letters, like light through a window at dusk.
            RadialGradient(colors: [.white.opacity(style == .tinted ? 0 : 0.18), .clear],
                           center: .init(x: 0.5, y: 0.55), startRadius: 0, endRadius: size * 0.55)
            NxTWordmark(size: size * 0.4, color: style == .tinted ? .white : .white)
                .shadow(color: .black.opacity(style == .tinted ? 0 : 0.18), radius: size * 0.02, y: size * 0.01)
                .offset(y: size * 0.01)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: rounded ? size * 0.225 : 0, style: .continuous))
    }
}
