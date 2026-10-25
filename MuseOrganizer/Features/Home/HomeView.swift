import SwiftUI

/// Landing screen: the next trip as an invitation-style cover, Muse's latest call, what needs you,
/// and a fast way to start something new.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewPlan = false

    private var trip: Plan? { model.plan("japan") }
    private var car: Plan? { model.plan("car") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    greeting
                    if let trip {
                        VStack(spacing: Space.s + 4) {
                            UpNextCover(plan: trip) { model.open(planID: trip.id) }
                            if let (plan, watch, advice) = topCall {
                                MuseCallRow(plan: plan, watch: watch, advice: advice, isDemo: model.priceWatch.isDemo) {
                                    model.open(planID: plan.id)
                                }
                            }
                        }
                    }
                    needsYou
                    startPlan
                    latest
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Avatar(member: Mock.me, size: 32)
                }
            }
            .sheet(isPresented: $showNewPlan) {
                NewPlanSheet {
                    showNewPlan = false
                    model.open(planID: "japan")
                }
            }
        }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .eyebrowStyle()
            Text("Good evening, Devin")
                .font(.display)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Muse

    /// The newest "book now" or "keep watching" call across plans: the one thing worth acting on today.
    private var topCall: (Plan, PriceWatch, PriceAdvice)? {
        model.plans
            .compactMap { plan in model.priceWatch.latestAdvice(for: plan.id).map { (plan, $0.0, $0.1) } }
            .filter { $0.2.verdict == .book || $0.2.verdict == .watch }
            .max { a, b in
                // Book-now calls beat keep-watching; then the newest wins.
                (a.2.verdict == .book ? 1 : 0, a.2.at) < (b.2.verdict == .book ? 1 : 0, b.2.at)
            }
    }

    private var otherCalls: [(Plan, PriceAdvice)] {
        model.plans
            .compactMap { plan in model.priceWatch.latestAdvice(for: plan.id).map { (plan, $0.1) } }
            .filter { ($0.1.verdict == .book || $0.1.verdict == .watch) && $0.1.id != topCall?.2.id }
    }

    // MARK: Needs you

    private var needsYou: some View {
        VStack(alignment: .leading, spacing: Space.s + 4) {
            SectionTitle(title: "Needs you", detail: "\(3 + otherCalls.count) things")
            Panel(padding: 0) {
                ForEach(otherCalls, id: \.1.id) { plan, advice in
                    ActionRow(symbol: advice.verdict.symbol, tint: Tint(strong: advice.verdict.color, soft: advice.verdict.color.opacity(0.12)),
                              title: advice.headline,
                              detail: "Muse · \(advice.verdict.title) · \(plan.name)") { model.open(planID: plan.id) }
                    Hairline(inset: 72)
                }
                if let trip {
                    ActionRow(symbol: "ticket", tint: .activities,
                              title: "Pick things to do",
                              detail: "\(trip.name) · nobody has voted yet") { model.open(planID: trip.id) }
                    Hairline(inset: 72)
                }
                if let car {
                    ActionRow(symbol: "calendar", tint: .dates,
                              title: "Book the dealer visit",
                              detail: "\(car.name) · Mom wants to talk to someone first") { model.open(planID: car.id) }
                    Hairline(inset: 72)
                }
                ActionRow(symbol: "square.and.arrow.down", tint: ChatSource.instagram.tint,
                          title: "\(model.pendingShared.count) links shared with you",
                          detail: "Maya, Jordan, and Sam · add them to a plan") { model.tab = .shared }
            }
        }
    }

    // MARK: Start a plan

    private var startPlan: some View {
        VStack(alignment: .leading, spacing: Space.s + 4) {
            SectionTitle(title: "Start a plan")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s + 4) {
                    template("Trip", "airplane", .flights)
                    template("Big purchase", "car.fill", .car)
                    template("Dinner", "fork.knife", .stays)
                    template("Event", "party.popper.fill", .activities)
                    template("Gift", "gift.fill", .dates)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 4) // room for the card shadow
            }
            .padding(.horizontal, -Space.m)
            .padding(.vertical, -Space.s - 4)
        }
    }

    /// Airbnb-style category tile: a big, colored glyph on a white card, the name underneath.
    private func template(_ title: String, _ symbol: String, _ tint: Tint) -> some View {
        Button { showNewPlan = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint.strong)
                    .frame(width: 52, height: 52)
                    .background(tint.soft, in: .circle)
                Spacer(minLength: Space.m)
                Text(title)
                    .font(.smallStrong)
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 104, height: 124, alignment: .topLeading)
            .padding(Space.m)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.l, style: .continuous))
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Start a \(title) plan")
    }

    // MARK: Latest from chats

    private var latest: some View {
        VStack(alignment: .leading, spacing: Space.s + 4) {
            SectionTitle(title: "From your chats")
            Panel(padding: 0) {
                ForEach(Array(model.plans.enumerated()), id: \.element.id) { index, plan in
                    if let post = plan.messages.last(where: { if case .planner = $0.body { true } else { false } }),
                       case .planner(let p) = post.body {
                        Button { model.open(planID: plan.id) } label: {
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack(spacing: Space.s) {
                                    PlannerLabel()
                                    Text("in \(plan.chatName)").font(.small).foregroundStyle(Palette.inkSecondary)
                                    Spacer()
                                    Text(post.time).font(.small).foregroundStyle(Palette.inkSecondary)
                                }
                                Text(p.text)
                                    .font(.bodyRegular)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                AppPill(source: plan.source)
                            }
                            .padding(Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressable)
                        if index < model.plans.count - 1 { Hairline(inset: Space.m) }
                    }
                }
            }
        }
    }
}

// MARK: - Up next cover

/// The next trip as an invitation: mood colors, the name in serif, a countdown, and who's going.
private struct UpNextCover: View {
    var plan: Plan
    var action: () -> Void

    private var daysAway: Int {
        let start = DateComponents(calendar: .current, year: 2027, month: 3, day: 26).date ?? .now
        return max(0, Calendar.current.dateComponents([.day], from: .now, to: start).day ?? 0)
    }

    var body: some View {
        Button(action: action) {
            PlanCover(theme: plan.cover, height: 300) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        GlassChip { Label("Up next", systemImage: "airplane") }
                        Spacer()
                        AvatarStack(members: plan.members, size: 30)
                    }
                    Spacer(minLength: Space.l)
                    Text(plan.name)
                        .font(.display)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    Text("\(plan.decided("Dates") ?? "Dates TBD") · \(daysAway) days to go")
                        .font(.bodyStrong)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: Space.s) {
                        CoverProgress(decided: plan.decidedCount, total: plan.decisions.count)
                        HStack(spacing: Space.s) {
                            Text("\(plan.decidedCount) of \(plan.decisions.count) decided")
                            Spacer(minLength: Space.s)
                            Text("Next: \(plan.nextStep)").lineLimit(1)
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                    .padding(Space.s + 4)
                    .glassEffect(.cover, in: .rect(cornerRadius: Radius.m, style: .continuous))
                    .padding(.top, Space.m)
                }
                .padding(Space.m + 2)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the plan")
    }
}

// MARK: - Muse's call

/// Hopper-style: one clear verdict, the headline, and the price line, right under the trip it's about.
private struct MuseCallRow: View {
    var plan: Plan
    var watch: PriceWatch
    var advice: PriceAdvice
    var isDemo: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                MuseMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(advice.verdict.title)
                            .font(.smallStrong)
                            .foregroundStyle(advice.verdict.color)
                        Text("· Muse\(isDemo ? " · demo" : "")")
                            .font(.small)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text(advice.headline)
                        .font(.bodyStrong)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Sparkline(prices: watch.prices, tint: advice.verdict.color)
                    .frame(width: 64, height: 32)
            }
            .padding(Space.m)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.l, style: .continuous))
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens \(plan.name)")
    }
}

/// Row with a quiet leading icon, used for to-dos.
struct ActionRow: View {
    var symbol: String
    var tint: Tint
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                TintTile(symbol: symbol, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.bodyStrong).foregroundStyle(Palette.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail).font(.small).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right").font(.small.weight(.semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.m - 2)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}
