import SwiftUI

struct TripPlanView: View {
    @Bindable var plan: Plan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                // Progress and the decisions behind it live in one panel, so the count isn't repeated.
                Panel(padding: Space.s + 6) {
                    PlanHeader(plan: plan)
                    DecisionList(decisions: plan.decisions, note: "Sam is away Mar 20–24. These dates avoid it.")
                        .padding(.top, Space.s + 4)
                }

                ForEach(OptionCategory.allCases) { category in
                    let items = plan.options.filter { $0.category == category }
                    if !items.isEmpty {
                        OptionBand(category: category, items: items, members: plan.members) { id, vote in
                            withAnimation(Motion.snappy) { plan.vote(id, vote) }
                        }
                    }
                }

                Panel {
                    Itinerary(days: plan.itinerary)
                }

                Panel {
                    VStack(spacing: Space.s) {
                        ShareLink(item: CalendarExport.file(for: plan),
                                  preview: SharePreview("\(plan.name).ics", image: Image(systemName: "calendar"))) {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.primary)
                        PostToChatButton(plan: plan)
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
    }
}

// MARK: - Options band
// Each category is its own colored band. Cards are compact so you can see a whole row without scrolling far.

private struct OptionBand: View {
    var category: OptionCategory
    var items: [BoardOption]
    var members: [Member]
    var onVote: (BoardOption.ID, BoardOption.Vote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 22, height: 22)
                    .background(category.tint.strong, in: .rect(cornerRadius: 6, style: .continuous))
                Text(category.rawValue).font(.smallStrong).foregroundStyle(Palette.ink)
                Text("\(items.count)").font(.small).foregroundStyle(Palette.inkSecondary)
                Spacer()
                Text("via \(items[0].source)").font(.caption).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.s + 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(items) { OptionCard(option: $0, members: members, onVote: onVote) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Space.s + 6)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, Space.s + 4)
        .background(category.tint.soft, in: .rect(cornerRadius: Radius.l, style: .continuous))
    }
}

struct OptionCard: View {
    var option: BoardOption
    var members: [Member]
    var onVote: (BoardOption.ID, BoardOption.Vote) -> Void

    /// Votes work like read receipts that go both ways: you see who voted once you've voted yourself.
    private var voters: [Member] {
        let others = members.filter { !$0.isMe }.prefix(max(0, option.upVotes - (option.myVote == .up ? 1 : 0)))
        return (option.myVote == .up ? [Mock.me] : []) + others
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs) {
                if option.isTopPick {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.accent)
                        .accessibilityLabel("Top pick")
                }
                if let from = option.sharedFrom {
                    Image(systemName: from.symbol).font(.caption2).foregroundStyle(from.tint.strong)
                        .accessibilityLabel("Shared from \(from.rawValue)")
                }
                Text(option.title).font(.smallStrong).foregroundStyle(Palette.ink).lineLimit(1)
            }
            Text(option.detail).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(option.price).font(.bodyStrong).figure().foregroundStyle(Palette.ink)
                Text(option.unit).font(.caption2).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            .padding(.top, 2)

            Text(option.tradeoff)
                .font(.caption2)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)

            HStack(spacing: Space.xs) {
                VoteControl(up: option.upVotes, down: option.downVotes, mine: option.myVote, compact: true) { onVote(option.id, $0) }
                Spacer(minLength: 0)
                if option.myVote != .none, !voters.isEmpty {
                    AvatarStack(members: voters, size: 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.top, 4)
        }
        .padding(Space.s + 2)
        .frame(width: 176, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.m, style: .continuous))
        .overlay {
            if option.isTopPick {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Itinerary (collapsed by default, each day expands on tap)

private struct Itinerary: View {
    var days: [ItineraryDay]
    @State private var expanded = false
    @State private var openDays: Set<ItineraryDay.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    expanded.toggle()
                    if expanded, openDays.isEmpty, let first = days.first { openDays = [first.id] }
                }
            } label: {
                HStack(spacing: Space.m) {
                    TintTile(symbol: "map.fill", tint: .dates, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Itinerary").font(.bodyStrong).foregroundStyle(Palette.ink)
                        Text("9 days · \(days.count) drafted so far · Tokyo, then Kyoto").font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.smallStrong)
                        .foregroundStyle(Palette.inkSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                VStack(spacing: Space.s) {
                    ForEach(days) { day in dayRow(day) }
                }
                .padding(.top, Space.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func dayRow(_ day: ItineraryDay) -> some View {
        let open = openDays.contains(day.id)
        let color = day.city == "Kyoto" ? Tint.stays.strong : Tint.flights.strong
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snappy) {
                    if open { openDays.remove(day.id) } else { openDays.insert(day.id) }
                }
            } label: {
                HStack(spacing: Space.s) {
                    Text("Day \(day.day)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 3)
                        .background(color, in: .capsule)
                    Text("\(day.date) · \(day.city)").font(.smallStrong).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(day.slots.count) stops").font(.caption).foregroundStyle(Palette.inkSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(day.slots) { slot in
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Text(slot.time).font(.caption).figure().foregroundStyle(Palette.inkSecondary)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slot.title).font(.small).foregroundStyle(Palette.ink)
                                Text(slot.detail).font(.caption).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.bottom, Space.s)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.m)
        .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.m, style: .continuous))
    }
}

enum CalendarExport {
    static func file(for plan: Plan) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(plan.name).ics")
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Huddle//Planner//EN
        BEGIN:VEVENT
        UID:\(plan.id)@huddle.app
        DTSTART;VALUE=DATE:20270326
        DTEND;VALUE=DATE:20270405
        SUMMARY:\(plan.name)
        DESCRIPTION:Planned with Huddle in \(plan.chatName).
        END:VEVENT
        END:VCALENDAR
        """
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
