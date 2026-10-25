import SwiftUI

/// One screen for every kind of plan: a compact cover, Muse's one-line price call, then tabs that
/// Muse picks from the request (a road trip never shows Flights, a dinner is just places and who's in).
struct PlanScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan
    @State private var tab: PlanTab = .overview

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.m, pinnedViews: [.sectionHeaders]) {
                PlanHeaderCover(plan: plan)
                    .padding(.horizontal, Space.m)
                MuseStrip(plan: plan)
                    .padding(.horizontal, Space.m)
                Section {
                    content
                        .id(tab)
                        .transition(.opacity)
                        .padding(.horizontal, Space.m)
                } header: {
                    PlanTabBar(plan: plan, selection: $tab)
                        .background(Palette.canvas)
                }
            }
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Palette.canvas)
        .refreshable { await model.priceWatch.check(plan.id) }
        .task { await model.priceWatch.load(plan) }
        .onChange(of: plan.tabs) { _, tabs in
            if !tabs.contains(tab) { tab = .overview }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .overview:
            PlanOverview(plan: plan) { next in withAnimation(Motion.snappy) { tab = next } }
        case .flights, .stays, .todo, .places:
            VStack(alignment: .leading, spacing: Space.m) {
                if let category = tab.category { OptionList(plan: plan, category: category) }
                if tab == .todo, plan.kind == .trip, !plan.itinerary.isEmpty {
                    Panel(padding: Space.s + 6) { Itinerary(days: plan.itinerary) }
                }
            }
        case .route, .gettingThere:
            MuseWorkingCard(text: tab == .route ? "Muse is mapping the drive: legs, stops and gas." : "Muse is checking trains and buses, step-free stations first.") {
                model.openThread(planID: plan.id)
            }
        case .guests:
            GuestList(plan: plan)
        case .money:
            MoneyView(plan: plan)
        case .options, .numbers, .prices:
            CarPlanView(plan: plan, tab: tab) { model.openThread(planID: plan.id) }
        }
    }
}

// MARK: - Cover

/// Compact cover: the group, the plan's name, and how close it is to decided.
private struct PlanHeaderCover: View {
    var plan: Plan

    private var subtitle: String? { plan.decided("Dates") ?? plan.decided("Day") }

    var body: some View {
        PlanCover(theme: plan.cover) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    GlassChip { Label(plan.chatName, systemImage: plan.source.symbol) }
                    Spacer()
                    AvatarStack(members: plan.members, size: 26)
                }
                Text(plan.name)
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(.top, Space.s)
                if let subtitle {
                    Text(subtitle).font(.smallStrong).foregroundStyle(.white.opacity(0.92))
                }
                CoverProgress(decided: plan.decidedCount, total: plan.decisions.count)
                    .padding(.top, Space.xs)
                Text(left)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(Space.m)
        }
        .accessibilityElement(children: .combine)
    }

    /// "2 things left to decide" reads easier than "3 of 5 decided".
    private var left: String {
        let n = plan.decisions.count - plan.decidedCount
        return n == 0 ? "Everything's decided" : "\(n) \(n == 1 ? "thing" : "things") left to decide"
    }
}

// MARK: - Muse strip

/// Muse's latest price call in one line. Tap for everything Muse is watching.
private struct MuseStrip: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    @State private var showAll = false

    var body: some View {
        if let (watch, advice) = model.priceWatch.latestAdvice(for: plan.id) {
            Button { showAll = true } label: {
                HStack(spacing: Space.s + 4) {
                    MuseMark(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(advice.verdict.title).font(.caption.weight(.bold)).foregroundStyle(advice.verdict.color)
                        Text(advice.headline).font(.smallStrong).foregroundStyle(Palette.ink).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Sparkline(prices: watch.prices, tint: advice.verdict.color)
                        .frame(width: 54, height: 24)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 4)
                .background(Palette.panel, in: .rect(cornerRadius: Radius.m, style: .continuous))
                .cardShadow()
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Shows every price Muse is watching")
            .sheet(isPresented: $showAll) {
                WatchListSheet(plan: plan)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Tab bar

/// Airbnb-style tabs with a sliding underline. A dot marks tabs waiting on a vote.
private struct PlanTabBar: View {
    var plan: Plan
    @Binding var selection: PlanTab
    @Namespace private var underline

    var body: some View {
        let tabs = plan.tabs
        VStack(spacing: 0) {
            if tabs.count <= 4 {
                // Few tabs share the width evenly, like Airbnb's category bar.
                HStack(spacing: 0) {
                    ForEach(tabs) { tabButton($0).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, Space.s)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(tabs) { tabButton($0) }
                    }
                    .padding(.horizontal, Space.s)
                }
            }
            Hairline()
        }
        .padding(.top, Space.xs)
    }

    private func tabButton(_ tab: PlanTab) -> some View {
        let selected = tab == selection
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(Motion.snappy) { selection = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? tab.tint.strong : Palette.inkSecondary)
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: 22)
                    .overlay(alignment: .topTrailing) {
                        if needsVote(tab) {
                            Circle().fill(Palette.accent).frame(width: 7, height: 7).offset(x: 6, y: -2)
                        }
                    }
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
                    .lineLimit(1)
                ZStack {
                    Capsule().fill(.clear).frame(height: 2.5)
                    if selected {
                        Capsule().fill(Palette.ink).frame(height: 2.5)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
            }
            .padding(.horizontal, Space.s + 2)
            .frame(minWidth: 64, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(needsVote(tab) ? "\(tab.title), needs your vote" : tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func needsVote(_ tab: PlanTab) -> Bool {
        if case .voting = plan.decision(for: tab)?.state { true } else { false }
    }
}

// MARK: - Overview

/// The answer screen: what to do next (one button), the budget, where everything stands, and what Muse understood.
private struct PlanOverview: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    var select: (PlanTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // A decision plan's next step is Muse's recommendation, with its own single action.
            if plan.kind == .decision {
                CarPlanView(plan: plan, tab: .overview) { model.openThread(planID: plan.id) }
            } else {
                nextStep
            }
            budget
            standing
            understood
        }
    }

    private var nextStep: some View {
        Panel(padding: Space.m + 2) {
            Text("What's next").eyebrowStyle()
            Text(plan.nextStep)
                .font(.title)
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)
            if let next = plan.nextTab {
                Button { select(next) } label: {
                    Label(next.category == nil ? "Open \(next.title)" : "Vote on \(next.title.lowercased())", systemImage: next.symbol)
                }
                .buttonStyle(.primary)
                .padding(.top, Space.m)
            }
        }
    }

    @ViewBuilder private var budget: some View {
        let lines = plan.costLines { model.priceWatch.watch(id: $0) }
        if let cap = plan.budgetPerPerson, !lines.isEmpty, plan.tabs.contains(.money) {
            let total = lines.reduce(0) { $0 + $1.perPerson }
            Button { select(.money) } label: {
                Panel(padding: Space.m + 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Budget").eyebrowStyle()
                        Spacer()
                        Text(total <= cap ? "\(Money.format(cap - total)) under" : "\(Money.format(total - cap)) over")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(total <= cap ? Palette.positive : Palette.critical)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Money.format(total)).font(.system(.title, design: .rounded, weight: .bold)).figure()
                            .foregroundStyle(Palette.ink).contentTransition(.numericText())
                        Text("of \(Money.format(cap)) each").font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, 2)
                    BudgetBar(fraction: total / cap)
                        .padding(.top, Space.s)
                }
            }
            .buttonStyle(.pressable)
        }
    }

    private var standing: some View {
        let rows = plan.tabs.filter { $0 != .overview && plan.decision(for: $0) != nil }
        return Group {
            if !rows.isEmpty {
                Panel(padding: 0) {
                    Text("Where things stand").eyebrowStyle()
                        .padding([.horizontal, .top], Space.m)
                        .padding(.bottom, Space.xs)
                    ForEach(Array(rows.enumerated()), id: \.element) { index, tab in
                        if index > 0 { Hairline(inset: Space.m + 44) }
                        Button { select(tab) } label: { StandingRow(tab: tab, decision: plan.decision(for: tab)!) }
                            .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    @ViewBuilder private var understood: some View {
        let setup = plan.setup
        if !setup.chips.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    MuseMark(size: 18)
                    Text("Muse set this up from your chat").font(.smallStrong).foregroundStyle(Palette.ink)
                }
                FlowLayout(spacing: 6) {
                    ForEach(setup.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.fill, in: .capsule)
                    }
                }
            }
            .padding(.horizontal, Space.xs)
            .padding(.top, Space.xs)
        }
    }
}

private struct StandingRow: View {
    var tab: PlanTab
    var decision: Decision

    var body: some View {
        HStack(spacing: Space.m) {
            TintTile(symbol: tab.symbol, tint: tab.tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title).font(.smallStrong).foregroundStyle(Palette.ink)
                Text(value).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            status
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + 4)
        .contentShape(.rect)
    }

    private var value: String {
        switch decision.state {
        case .decided(let s), .voting(let s), .open(let s): s
        }
    }

    @ViewBuilder private var status: some View {
        switch decision.state {
        case .decided: Label("Done", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Palette.positive)
        case .voting: Text("Vote").font(.caption.weight(.bold)).foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Palette.accent, in: .capsule)
        case .open: Text("Open").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
        }
    }
}

private struct BudgetBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                Capsule().fill(fraction <= 1 ? Palette.positive : Palette.critical)
                    .frame(width: geo.size.width * min(1, max(0.04, fraction)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Money

/// Per-person cost from what's leading in each tab, against the group's budget.
private struct MoneyView: View {
    @Environment(AppModel.self) private var model
    var plan: Plan

    var body: some View {
        let lines = plan.costLines { model.priceWatch.watch(id: $0) }
        let total = lines.reduce(0) { $0 + $1.perPerson }
        VStack(alignment: .leading, spacing: Space.m) {
            Panel(padding: Space.m + 2) {
                Text("Per person").eyebrowStyle()
                Text(Money.format(total)).font(.system(.largeTitle, design: .rounded, weight: .bold)).figure()
                    .foregroundStyle(Palette.ink).contentTransition(.numericText())
                if let cap = plan.budgetPerPerson {
                    Text(total <= cap ? "\(Money.format(cap - total)) under the \(Money.format(cap)) budget" : "\(Money.format(total - cap)) over the \(Money.format(cap)) budget")
                        .font(.smallStrong)
                        .foregroundStyle(total <= cap ? Palette.positive : Palette.critical)
                    BudgetBar(fraction: total / cap).padding(.top, Space.s)
                }
            }
            Panel(padding: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Hairline(inset: Space.m) }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.label).font(.smallStrong).foregroundStyle(Palette.ink)
                            Text(line.detail).font(.caption).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        Text(Money.format(line.perPerson)).font(.smallStrong).figure().foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s + 4)
                }
                if lines.isEmpty {
                    Text("Costs show up here as the group picks options.")
                        .font(.small).foregroundStyle(Palette.inkSecondary).padding(Space.m)
                }
            }
            Label("Based on what's leading in each tab. Muse updates it when prices move.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, Space.xs)
        }
    }
}

// MARK: - Who's in

private struct GuestList: View {
    var plan: Plan

    var body: some View {
        let maybe = plan.members.last { !$0.isMe }
        Panel(padding: 0) {
            ForEach(Array(plan.members.enumerated()), id: \.element.id) { index, member in
                if index > 0 { Hairline(inset: Space.m + 48) }
                HStack(spacing: Space.m) {
                    Avatar(member: member, size: 36)
                    Text(member.isMe ? "\(member.name) (you)" : member.name).font(.bodyRegular).foregroundStyle(Palette.ink)
                    Spacer()
                    if member.id == maybe?.id {
                        Text("Maybe").font(.caption.weight(.semibold)).foregroundStyle(Palette.caution)
                    } else {
                        Label("Going", systemImage: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Palette.positive)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 2)
            }
        }
    }
}

// MARK: - Muse is still on it

private struct MuseWorkingCard: View {
    var text: String
    var ask: () -> Void

    var body: some View {
        Panel(padding: Space.m + 2) {
            HStack(spacing: Space.s + 4) {
                MuseMark(size: 28)
                Text(text).font(.bodyRegular).foregroundStyle(Palette.ink)
            }
            Button("Ask Muse in the chat", action: ask)
                .buttonStyle(.secondary)
                .padding(.top, Space.m)
        }
    }
}
