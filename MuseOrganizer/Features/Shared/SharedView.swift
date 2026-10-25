import SwiftUI

/// Everything people shared into Huddle from other apps: reels, posts, links, messages.
/// Sharing is how Instagram works best, so Huddle meets it there instead of trying to read DMs.
struct SharedView: View {
    @Environment(AppModel.self) private var model
    /// Inside Messages it shares that screen's navigation instead of bringing its own.
    var embedded = false

    private var pending: [SharedItem] { model.shared.filter { !$0.added } }
    private var added: [SharedItem] { model.shared.filter(\.added) }

    var body: some View {
        if embedded {
            inbox
        } else {
            NavigationStack { inbox.navigationTitle("Shared") }
        }
    }

    private var inbox: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if pending.isEmpty {
                        Panel {
                            VStack(spacing: Space.s) {
                                Image(systemName: "tray")
                                    .font(.title)
                                    .foregroundStyle(Palette.inkFaint)
                                Text("You're all caught up").font(.bodyStrong).foregroundStyle(Palette.ink)
                                Text("Anything your group shares into NxT shows up here.")
                                    .font(.small).foregroundStyle(Palette.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.l)
                        }
                    } else {
                        ForEach(pending) { item in
                            SharedCard(item: item, planName: model.plan(item.planID ?? "")?.name) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                model.add(item)
                            }
                        }
                    }

                    if !added.isEmpty {
                        Panel {
                            PanelHeader(title: "Added to plans", subtitle: "\(added.count) so far", symbol: "checkmark", tint: .activities)
                                .padding(.bottom, Space.s)
                            ForEach(Array(added.enumerated()), id: \.element.id) { i, item in
                                HStack(spacing: Space.m) {
                                    Text(item.title).font(.bodyRegular).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text(model.plan(item.planID ?? "")?.name ?? "")
                                        .font(.small).foregroundStyle(Palette.inkSecondary)
                                }
                                .frame(minHeight: 44)
                                if i < added.count - 1 { Hairline() }
                            }
                        }
                    }

                    HowSharingWorks()
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.canvas)
            .refreshable { model.reloadShared() }
    }
}

private struct SharedCard: View {
    var item: SharedItem
    var planName: String?
    var onAdd: () -> Void

    private var source: ChatSource? { ChatSource(rawValue: item.source) }
    private var categoryTint: Tint {
        switch item.category {
        case "Flights": .flights
        case "Stays": .stays
        case "Things to do": .activities
        default: .money
        }
    }

    var body: some View {
        Panel(padding: 0) {
            HStack(alignment: .top, spacing: Space.m) {
                TintTile(symbol: source?.symbol ?? "safari", tint: source?.tint ?? .neutral, size: 48)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(item.sharedBy) shared from \(item.source) · \(item.date.formatted(.relative(presentation: .named)))")
                        .font(.small).foregroundStyle(Palette.inkSecondary)
                    Text(item.title).font(.heading).foregroundStyle(Palette.ink)
                    if !item.note.isEmpty {
                        Text(item.note).font(.small).foregroundStyle(Palette.ink)
                    }
                    if let url = item.url, let host = URL(string: url)?.host() {
                        Label(host, systemImage: "link").font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)

            HStack(spacing: Space.s) {
                if let category = item.category {
                    Text(category)
                        .font(.smallStrong)
                        .foregroundStyle(categoryTint.strong)
                        .padding(.horizontal, Space.s + 2)
                        .padding(.vertical, Space.xs)
                        .background(categoryTint.soft, in: .capsule)
                }
                if let planName {
                    Text(planName).font(.small).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s)
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.smallStrong)
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 36)
                        .background(Palette.accent, in: .capsule)
                }
                .buttonStyle(.pressable)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(Palette.fill.opacity(0.6))
        }
        .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
    }
}

private struct HowSharingWorks: View {
    var body: some View {
        Panel(fill: Palette.accentFill) {
            Text("Share from any app")
                .font(.bodyStrong).foregroundStyle(Palette.ink)
                .padding(.bottom, Space.s)
            VStack(alignment: .leading, spacing: Space.s) {
                step(1, "Tap Share on a reel, post, message, or link")
                step(2, "Choose NxT, then pick the plan")
                step(3, "It becomes an option the group can vote on")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(n)").font(.smallStrong).figure().foregroundStyle(Palette.accent).frame(width: 16)
            Text(text).font(.small).foregroundStyle(Palette.ink)
        }
    }
}
