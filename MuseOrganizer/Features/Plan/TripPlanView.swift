import SwiftUI

struct TripPlanView: View {
    @Bindable var plan: Plan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Panel { PlanHeader(plan: plan) }

                Panel {
                    PanelHeader(title: "Decisions", subtitle: "\(plan.decidedCount) of \(plan.decisions.count) settled",
                                symbol: "checklist", tint: .planner)
                    DecisionList(decisions: plan.decisions) { d in
                        d.title == "Dates" ? "Sam is away Mar 20–24. These dates avoid it." : nil
                    }
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

                PlanFolderPanel(plan: plan)

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
// Each category is its own colored band so Flights, Stays, and Things to do never blur together.

private struct OptionBand: View {
    var category: OptionCategory
    var items: [BoardOption]
    var members: [Member]
    var onVote: (BoardOption.ID, BoardOption.Vote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: category.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(category.tint.strong, in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue).font(.heading).foregroundStyle(Palette.ink)
                    Text("\(items.count) options · via \(items[0].source) · \(items[0].fetched)")
                        .font(.small).foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(items) { OptionCard(option: $0, members: members, onVote: onVote) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Space.m)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, Space.m)
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
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    if option.isTopPick {
                        Label("Top pick", systemImage: "star.fill")
                            .font(.smallStrong)
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, 2)
                            .background(Palette.accent, in: .capsule)
                    }
                    if let from = option.sharedFrom, let by = option.sharedBy {
                        Label("\(by) via \(from.rawValue)", systemImage: from.symbol)
                            .font(.smallStrong)
                            .foregroundStyle(from.tint.strong)
                    }
                    if !option.isTopPick && option.sharedFrom == nil {
                        Text(option.category.rawValue).font(.smallStrong).foregroundStyle(option.category.tint.strong)
                    }
                }
                Text(option.title).font(.bodyStrong).foregroundStyle(Palette.ink).lineLimit(1)
                Text(option.detail).font(.small).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(option.price).font(.hero).figure().foregroundStyle(Palette.ink)
                Text(option.unit).font(.small).foregroundStyle(Palette.inkSecondary)
            }

            Text(option.tradeoff)
                .font(.small)
                .foregroundStyle(Palette.ink)
                .lineLimit(2, reservesSpace: true)

            Hairline()

            HStack {
                VoteControl(up: option.upVotes, down: option.downVotes, mine: option.myVote) { onVote(option.id, $0) }
                Spacer(minLength: Space.s)
                if option.myVote == .none {
                    if option.upVotes + option.downVotes > 0 {
                        Label("Vote to see who", systemImage: "eye.slash")
                            .font(.small)
                            .foregroundStyle(Palette.inkSecondary)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Vote to see who voted")
                    }
                } else if !voters.isEmpty {
                    AvatarStack(members: voters, size: 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .padding(Space.m)
        .frame(width: 296, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.m + 4, style: .continuous))
        .overlay {
            if option.isTopPick {
                RoundedRectangle(cornerRadius: Radius.m + 4, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
            }
        }
    }
}

// MARK: - Itinerary

private struct Itinerary: View {
    var days: [ItineraryDay]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PanelHeader(title: "Itinerary", subtitle: "Draft · updates as you vote", symbol: "map.fill", tint: .dates)
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.s) {
                        Text("Day \(day.day)")
                            .font(.smallStrong)
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, Space.s + 2)
                            .padding(.vertical, Space.xs)
                            .background(day.city == "Kyoto" ? Tint.stays.strong : Tint.flights.strong, in: .capsule)
                        Text("\(day.date) · \(day.city)").font(.smallStrong).foregroundStyle(Palette.ink)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(day.slots.enumerated()), id: \.element.id) { i, slot in
                            HStack(alignment: .top, spacing: Space.m) {
                                Text(slot.time)
                                    .font(.small).figure()
                                    .foregroundStyle(Palette.inkSecondary)
                                    .frame(width: 72, alignment: .leading)
                                VStack(spacing: 0) {
                                    Circle()
                                        .strokeBorder(Palette.panel, lineWidth: 2)
                                        .background(Circle().fill(day.city == "Kyoto" ? Tint.stays.strong : Tint.flights.strong))
                                        .frame(width: 12, height: 12)
                                        .padding(.top, 4)
                                    if i < day.slots.count - 1 {
                                        Rectangle().fill(Palette.separator).frame(width: 2).frame(maxHeight: .infinity)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slot.title).font(.bodyRegular).foregroundStyle(Palette.ink)
                                    Text(slot.detail).font(.small).foregroundStyle(Palette.inkSecondary)
                                }
                                .padding(.bottom, Space.l)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(Space.m)
                    .background(Palette.fill.opacity(0.6), in: .rect(cornerRadius: Radius.m, style: .continuous))
                }
            }
        }
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
