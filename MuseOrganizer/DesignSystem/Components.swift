import SwiftUI

// MARK: - Avatars

struct Avatar: View {
    var member: Member
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let photo = member.photo, let image = UIImage(named: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(member.initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(member.tint.strong)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(member.tint.soft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityLabel(member.name)
    }
}

struct AvatarStack: View {
    var members: [Member]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -size / 3) {
            ForEach(members.prefix(4)) { m in
                Avatar(member: m, size: size)
                    .overlay(Circle().stroke(Palette.panel, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(members.count) people")
    }
}

// MARK: - Planner identity
// Indigo is the Planner's color. No sparkles, no gradients.

struct PlannerLabel: View {
    var working = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 8, height: 8)
                .opacity(working ? 0.4 : 1)
                .animation(working ? .easeInOut(duration: 0.6).repeatForever() : .default, value: working)
            Text("Planner")
                .font(.smallStrong)
                .foregroundStyle(Palette.accent)
        }
    }
}

// MARK: - Linked chat label

struct SourceLabel: View {
    var source: ChatSource
    var chatName: String

    var body: some View {
        Label {
            Text("\(chatName) on \(source.rawValue)")
        } icon: {
            Image(systemName: source.symbol)
        }
        .font(.small)
        .foregroundStyle(Palette.inkSecondary)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Decision progress

struct DecisionProgress: View {
    var decided: Int
    var total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < decided ? Palette.accent : Palette.fillStrong)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(decided) of \(total) decided")
    }
}

// MARK: - Votes

struct VoteControl: View {
    var up: Int
    var down: Int
    var mine: BoardOption.Vote
    var onVote: (BoardOption.Vote) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(.up, count: up, symbol: "hand.thumbsup")
            Rectangle().fill(Palette.separator).frame(width: 1, height: 20)
            button(.down, count: down, symbol: "hand.thumbsdown")
        }
        .background(Palette.fill, in: .capsule)
    }

    private func button(_ vote: BoardOption.Vote, count: Int, symbol: String) -> some View {
        let selected = mine == vote
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onVote(vote)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? symbol + ".fill" : symbol)
                    .contentTransition(.symbolEffect(.replace))
                Text("\(count)").figure().contentTransition(.numericText())
            }
            .font(.smallStrong)
            .foregroundStyle(selected ? Palette.accent : Palette.inkSecondary)
            .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vote == .up ? "Yes" : "No"), \(count) votes")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Panels
// Every distinct area of a screen is a Panel on the gray canvas, so sections never blur together.

struct Panel<Content: View>: View {
    var padding: CGFloat = Space.m
    var fill: Color = Palette.panel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: Radius.l, style: .continuous))
    }
}

/// Colored icon tile that gives each kind of thing its identity.
struct TintTile: View {
    var symbol: String
    var tint: Tint
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint.strong)
            .frame(width: size, height: size)
            .background(tint.soft, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Section heading with a colored tile, used at the top of each panel.
struct PanelHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String
    var tint: Tint
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.m) {
            TintTile(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.heading).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.small).foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String, tint: Tint) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// App label with its recognizable color, e.g. a green "WhatsApp" pill. Words, never logos.
struct AppPill: View {
    var source: ChatSource

    var body: some View {
        Label(source.rawValue, systemImage: source.symbol)
            .font(.smallStrong)
            .foregroundStyle(source.tint.strong)
            .padding(.horizontal, Space.s + 2)
            .padding(.vertical, Space.xs)
            .background(source.tint.soft, in: .capsule)
    }
}

/// 1-pt rule that never disappears to sub-pixel rounding.
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1).padding(.leading, inset)
    }
}

// MARK: - Section header

struct SectionTitle: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.heading).foregroundStyle(Palette.ink)
            Spacer()
            if let detail {
                Text(detail).font(.small).foregroundStyle(Palette.inkSecondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyStrong)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.accent.opacity(isEnabled ? 1 : 0.35), in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyStrong)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
