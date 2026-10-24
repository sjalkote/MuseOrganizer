import SwiftUI

/// How Huddle plugs into the apps your group already uses.
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Huddle works inside the chats you already have. It never posts on its own, and it only sees what someone mentions it in or shares with it.")
                        .font(.small)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Space.s)
                        .padding(.bottom, Space.s)

                    IntegrationCard(
                        source: .imessage,
                        status: "Ready",
                        summary: "Send a plan card into any conversation. Friends vote right in the bubble, no download needed to see it.",
                        steps: ["In a conversation, tap + then Huddle", "Pick a plan to send as a card", "Votes from the bubble sync to the plan"],
                        sees: "Only the plan cards you send",
                        actionTitle: "Open Messages",
                        action: { ChatBridge.open(ChatBridge.openURL(for: .imessage)) }
                    )

                    IntegrationCard(
                        source: .whatsapp,
                        status: "Ready",
                        summary: "Share a message or a whole chat into Huddle to start a plan. Post updates back with one tap.",
                        steps: ["In WhatsApp, share a message or Export Chat to Huddle", "Planner reads only what you shared", "Tap Post update to send the summary back"],
                        sees: "Only messages you share with it",
                        actionTitle: model.plan("japan").map { "Post update to \($0.chatName)" } ?? "Open WhatsApp",
                        action: {
                            if let plan = model.plan("japan") {
                                if !ChatBridge.open(ChatBridge.composeURL(for: .whatsapp, text: plan.chatUpdate)) {
                                    model.tab = .plans
                                    model.plansPath = ["japan"]
                                }
                            }
                        },
                        footnote: "Next: Planner as a WhatsApp Business contact in groups you create with it."
                    )

                    IntegrationCard(
                        source: .instagram,
                        status: "Ready",
                        summary: "Saw a spot in a reel? Share it to Huddle and it lands in the plan as something to vote on.",
                        steps: ["Tap Share on any reel or post", "Choose Huddle and pick the plan", "Planner looks up the place and price"],
                        sees: "Only the posts you share",
                        actionTitle: "See shared items",
                        action: { model.tab = .shared }
                    )

                    googleDrive

                    poweredBy
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.canvas)
            .navigationTitle("Apps")
        }
    }

    private var googleDrive: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    TintTile(symbol: "folder.fill", tint: .stays, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Drive").font(.heading).foregroundStyle(Palette.ink)
                        if let account = model.googleAccount {
                            Label("Connected as \(account)", systemImage: "checkmark.circle.fill")
                                .font(.smallStrong).foregroundStyle(Palette.positive)
                        } else {
                            Text("Not connected").font(.smallStrong).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Spacer()
                }
                Text("Turn a decided plan into a shareable folder: a budget Sheet, an itinerary Doc, and everything SerpApi found.")
                    .font(.bodyRegular).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m)

            VStack(alignment: .leading, spacing: Space.s) {
                Label("Planner sees: only the files it creates", systemImage: "lock.fill")
                    .font(.small).foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(Tint.stays.soft)

            Group {
                if model.googleAccount == nil {
                    Button("Connect Google Drive") { model.googleAccount = "Devin T" }
                } else {
                    Button("Disconnect") { model.googleAccount = nil }
                }
            }
            .buttonStyle(.secondary)
            .padding(Space.m)
        }
        .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
    }

    private var poweredBy: some View {
        Panel {
            PanelHeader(title: "Under the hood", symbol: "cpu", tint: .planner)
                .padding(.bottom, Space.s)
            row("Muse Spark", "Reads the thread and decides what to look up")
            Hairline(inset: 0)
            row("SerpApi", "Live flights, hotels, places, and prices")
            Hairline(inset: 0)
            row("Calendar", "Finds dates that work for everyone")
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.bodyStrong).foregroundStyle(Palette.ink)
            Text(detail).font(.small).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

private struct IntegrationCard: View {
    var source: ChatSource
    var status: String
    var summary: String
    var steps: [String]
    var sees: String
    var actionTitle: String
    var action: () -> Void
    var footnote: String? = nil

    var body: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    TintTile(symbol: source.symbol, tint: source.tint, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.rawValue).font(.heading).foregroundStyle(Palette.ink)
                        Label(status, systemImage: "checkmark.circle.fill")
                            .font(.smallStrong)
                            .foregroundStyle(Palette.positive)
                    }
                    Spacer()
                }
                Text(summary).font(.bodyRegular).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m)

            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(i + 1)")
                            .font(.smallStrong).figure()
                            .foregroundStyle(source.tint.strong)
                            .frame(width: 20, height: 20)
                            .background(Palette.panel, in: .circle)
                        Text(step).font(.small).foregroundStyle(Palette.ink)
                    }
                }
                Label("Planner sees: \(sees)", systemImage: "lock.fill")
                    .font(.small)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(source.tint.soft)

            VStack(alignment: .leading, spacing: Space.s) {
                Button(actionTitle, action: action)
                    .buttonStyle(.secondary)
                if let footnote {
                    Text(footnote).font(.small).foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(Space.m)
        }
        .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
    }
}
