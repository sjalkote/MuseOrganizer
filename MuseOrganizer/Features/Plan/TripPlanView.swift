import SwiftUI

// Pieces of a trip's tabs: the option list each tab shows, and the day-by-day itinerary.

// MARK: - Options

struct OptionList: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    var tab: ShownTab

    private var items: [BoardOption] { plan.options(for: tab) }
    private var leaderID: BoardOption.ID? {
        items.filter { $0.upVotes > 0 }.max { $0.upVotes < $1.upVotes }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("Nothing on \(tab.title) yet. Ask Muse in the chat and it will say when it adds some.")
                    .font(.small).foregroundStyle(Palette.inkSecondary)
                    .padding(Space.m)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, option in
                if index > 0 { Divider().padding(.leading, Space.s + 6) }
                OptionRow(option: option, members: plan.members, isLeader: option.id == leaderID,
                          watch: model.priceWatch.watch(id: option.watchID)) { id, vote in
                    withAnimation(Motion.snappy) { plan.vote(id, vote) }
                }
            }
            if let source = items.first?.source {
                Text("From \(source)")
                    .font(.caption2).foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, Space.s + 6)
                    .padding(.bottom, Space.s + 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.l, style: .continuous))
        .cardShadow()
    }
}

/// One option: what it is and what it costs, why you'd pick it, and your vote. Price moves come from Muse's watch.
private struct OptionRow: View {
    var option: BoardOption
    var members: [Member]
    var isLeader: Bool
    var watch: PriceWatch?
    var onVote: (BoardOption.ID, BoardOption.Vote) -> Void

    /// You see who voted once you've voted yourself.
    private var voters: [Member] {
        let others = members.filter { !$0.isMe }.prefix(max(0, option.upVotes - (option.myVote == .up ? 1 : 0)))
        return (option.myVote == .up ? [Mock.me] : []) + others
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let from = option.sharedFrom {
                            Image(systemName: from.symbol).font(.caption2).foregroundStyle(from.tint.strong)
                                .accessibilityLabel("Shared from \(from.rawValue)")
                        }
                        Text(option.title).font(.bodyStrong).foregroundStyle(Palette.ink).lineLimit(1)
                        if isLeader {
                            Label("Leading", systemImage: "crown.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Palette.accentFill, in: .capsule)
                        }
                    }
                    Text(option.detail).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText).font(.system(.title3, design: .rounded, weight: .bold)).figure().foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    if !option.unit.isEmpty {
                        Text(option.unit).font(.caption2).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    }
                    if let change = watch?.change { PriceChange(change: change) }
                }
            }

            Text(option.tradeoff)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)

            HStack(spacing: Space.s) {
                VoteControl(up: option.upVotes, down: option.downVotes, mine: option.myVote, compact: true) { onVote(option.id, $0) }
                if option.myVote != .none, !voters.isEmpty {
                    AvatarStack(members: voters, size: 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                Spacer(minLength: 0)
                if let watch {
                    Label(watch.isAtLow ? "Lowest seen" : "Watching", systemImage: watch.isAtLow ? "arrow.down.circle.fill" : "eye")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(watch.isAtLow ? Palette.positive : Palette.inkSecondary)
                }
            }
        }
        .padding(.horizontal, Space.s + 6)
        .padding(.vertical, Space.s + 4)
        .accessibilityElement(children: .contain)
    }

    /// The live price when Muse is watching it, else what the search found.
    private var priceText: String {
        if let current = watch?.current { return Money.format(current) }
        return option.price.isEmpty ? "—" : option.price
    }
}

// MARK: - Itinerary (collapsed by default, each day expands on tap)

struct Itinerary: View {
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
                    TintTile(symbol: "map.fill", tint: .dates, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Itinerary").font(.smallStrong).foregroundStyle(Palette.ink)
                        Text("9 days · \(days.count) drafted · Tokyo, then Kyoto").font(.caption).foregroundStyle(Palette.inkSecondary)
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
                .padding(.top, Space.s + 4)
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
