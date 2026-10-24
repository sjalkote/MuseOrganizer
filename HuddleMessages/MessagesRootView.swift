import SwiftUI

/// Compact: pick a plan to send. Expanded on a received card: one-tap voting.
struct MessagesRootView: View {
    var plans: [PlanSnapshot]
    var card: PlanCard?
    var send: (PlanSnapshot) -> Void
    var vote: (PlanCard, String) -> Void

    var body: some View {
        Group {
            if let card {
                VoteView(card: card, vote: vote)
            } else {
                PickPlanView(plans: plans, send: send)
            }
        }
        .tint(Palette.accent)
    }
}

private struct PickPlanView: View {
    var plans: [PlanSnapshot]
    var send: (PlanSnapshot) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(plans) { plan in
                    Button { send(plan) } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Send plan").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                            Text(plan.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                            Text("\(plan.decided) of \(plan.total) decided · \(plan.chatName)")
                                .font(.footnote).foregroundStyle(Palette.inkSecondary)
                            Spacer(minLength: 0)
                            Text(plan.memberNames.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                        .padding(Space.m)
                        .frame(width: 220, height: 132, alignment: .topLeading)
                        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send \(plan.name)")
                }
            }
            .padding(Space.m)
        }
    }
}

private struct VoteView: View {
    var card: PlanCard
    var vote: (PlanCard, String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(card.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Tap one to vote. Everyone in this conversation sees the update.")
                        .font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
                ForEach(card.options) { option in
                    Button { vote(card, option.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text(option.detail).font(.footnote).foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(option.price).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
                                Text("\(option.votes) votes").font(.footnote).monospacedDigit().foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(Space.m)
                        .frame(minHeight: 64)
                        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if let last = card.lastAction {
                    Text(last).font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(Space.m)
        }
    }
}

/// The image in the message bubble.
struct CardArt: View {
    var card: PlanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HUDDLE").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(card.decided) of \(card.total) decided").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            Text(card.name).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 0)
            ForEach(card.options.prefix(3)) { option in
                HStack {
                    Text(option.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text("\(option.votes)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .background(Color(hex: 0x4F46E5))
    }
}
