import SwiftUI

/// Each plan gets its own cover, the way an Apple Invites or Partiful invite does: a soft mesh of colors
/// that sets the mood, with the plan's name in the serif display face and glass chips on top.
struct CoverTheme {
    /// Nine colors, a 3×3 mesh read left to right, top to bottom. Keep the top-left dark so white text reads.
    var colors: [Color]

    static let japanDusk = CoverTheme(colors: [
        Color(hex: 0x2B1E46), Color(hex: 0x4A2A5E), Color(hex: 0x23305E),
        Color(hex: 0xB8506F), Color(hex: 0xE5797A), Color(hex: 0x9C4F86),
        Color(hex: 0xF7B48E), Color(hex: 0xFFC6A6), Color(hex: 0xF1A3A8),
    ])

    static let sageRoad = CoverTheme(colors: [
        Color(hex: 0x16302E), Color(hex: 0x23443F), Color(hex: 0x182A33),
        Color(hex: 0x3F6F62), Color(hex: 0x6E9A82), Color(hex: 0x355E62),
        Color(hex: 0xCDBF98), Color(hex: 0xE2D5B4), Color(hex: 0xB4C6AA),
    ])
}

extension Plan {
    var cover: CoverTheme { kind == .trip ? .japanDusk : .sageRoad }
}

struct PlanCover<Content: View>: View {
    var theme: CoverTheme
    var height: CGFloat? = nil
    @ViewBuilder var content: Content

    // Slightly uneven points so the mesh looks painted rather than computed.
    private let points: [SIMD2<Float>] = [
        [0, 0], [0.55, 0], [1, 0],
        [0, 0.45], [0.62, 0.52], [1, 0.4],
        [0, 1], [0.4, 1], [1, 1],
    ]

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background {
                MeshGradient(width: 3, height: 3, points: points, colors: theme.colors)
                    .overlay {
                        // Darkens the top and bottom edges a touch so white text always clears WCAG contrast.
                        LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0),
                                               .init(color: .clear, location: 0.45),
                                               .init(color: .clear, location: 0.6),
                                               .init(color: .black.opacity(0.22), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .clipShape(.rect(cornerRadius: Radius.xl, style: .continuous))
            .cardShadow()
    }
}

extension Glass {
    /// Frosted glass with a dark tint, so white text reads on any part of a cover.
    static var cover: Glass { .regular.tint(.black.opacity(0.28)) }
}

/// A frosted chip that sits on a cover.
struct GlassChip<Label: View>: View {
    static var scrim: Color { .black.opacity(0.28) }
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(Self.scrim), in: .capsule)
    }
}

/// White progress segments for use on a cover.
struct CoverProgress: View {
    var decided: Int
    var total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule().fill(.white.opacity(i < decided ? 0.95 : 0.3)).frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(decided) of \(total) decided")
    }
}
