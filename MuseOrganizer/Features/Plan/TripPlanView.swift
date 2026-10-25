import SwiftUI

/// The trip, top to bottom: where it stands, what Muse is seeing in prices, then one category of options at a time.
struct TripPlanView: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan
    @State private var category: OptionCategory = .flights

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                TripCover(plan: plan)
                MuseWatchCard(plan: plan)

                VStack(alignment: .leading, spacing: Space.m) {
                    CategoryPicker(plan: plan, selection: $category)
                    OptionList(plan: plan, category: category)
                        .id(category)
                        .transition(.opacity)
                }

                Panel(padding: Space.s + 6) {
                    Itinerary(days: plan.itinerary)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .refreshable { await model.priceWatch.check(plan.id) }
        .task { await model.priceWatch.load(plan) }
    }
}

// MARK: - Cover

/// The trip as an invitation: mood colors, dates and budget, who's going, and how close it is to decided.
private struct TripCover: View {
    var plan: Plan

    var body: some View {
        PlanCover(theme: plan.cover) {
            VStack(alignment: .leading, spacing: Space.s + 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.decided("Dates") ?? "Dates not set")
                            .font(.title)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            if let budget = plan.decided("Budget") {
                                GlassChip { Label(budget, systemImage: "dollarsign.circle") }
                            }
                            GlassChip { Label(plan.chatName, systemImage: plan.source.symbol) }
                        }
                    }
                    Spacer(minLength: Space.s)
                    AvatarStack(members: plan.members, size: 28)
                }
                CoverProgress(decided: plan.decidedCount, total: plan.decisions.count)
                    .padding(.top, Space.s)
                HStack(spacing: Space.s) {
                    Text("\(plan.decidedCount) of \(plan.decisions.count) decided")
                    Spacer(minLength: 0)
                    Text("Next: \(plan.nextStep)").lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
            }
            .padding(Space.m + 2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Category picker

/// Airbnb-style tabs: a glyph over the name, an underline that slides to the selected one,
/// and each tab's checklist status underneath so the old decision grid isn't needed.
private struct CategoryPicker: View {
    var plan: Plan
    @Binding var selection: OptionCategory
    @Namespace private var underline

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(OptionCategory.allCases) { category in
                    let selected = selection == category
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(Motion.snappy) { selection = category }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 22, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(selected ? category.tint.strong : Palette.inkSecondary)
                                .symbolEffect(.bounce, value: selected)
                                .frame(height: 26)
                            Text(shortName(category))
                                .font(.smallStrong)
                                .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
                            status(category)
                            ZStack {
                                Capsule().fill(.clear).frame(height: 2.5)
                                if selected {
                                    Capsule().fill(Palette.ink).frame(width: 36, height: 2.5)
                                        .matchedGeometryEffect(id: "underline", in: underline)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Hairline()
        }
    }

    private func shortName(_ c: OptionCategory) -> String { c == .activities ? "To do" : c.rawValue }

    @ViewBuilder private func status(_ category: OptionCategory) -> some View {
        switch plan.decision(for: category)?.state {
        case .decided:
            Label("Decided", systemImage: "checkmark")
                .font(.caption2.weight(.semibold)).foregroundStyle(Palette.positive)
        case .voting:
            Label("Voting", systemImage: "circle.fill")
                .font(.caption2.weight(.semibold)).imageScale(.small).foregroundStyle(Palette.accent)
        default:
            Text("Open").font(.caption2.weight(.medium)).foregroundStyle(Palette.inkSecondary)
        }
    }
}

// MARK: - Options

private struct OptionList: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    var category: OptionCategory

    private var items: [BoardOption] { plan.options.filter { $0.category == category } }
    private var leaderID: BoardOption.ID? {
        items.filter { $0.upVotes > 0 }.max { $0.upVotes < $1.upVotes }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(model.priceWatch.api == nil ? "No options yet." : "Searching \(category.rawValue.lowercased())…")
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
