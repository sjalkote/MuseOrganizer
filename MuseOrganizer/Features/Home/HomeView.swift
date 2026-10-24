import SwiftUI

/// Landing screen: what's coming up, what needs you, and a fast way to start something new.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewPlan = false

    private var trip: Plan? { model.plan("japan") }
    private var car: Plan? { model.plan("car") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    greeting
                        .padding(.bottom, Space.s)
                    if let trip { UpNextCard(plan: trip) { model.open(planID: trip.id) } }
                    needsYou
                    startPlan
                    latest
                }
                .padding(.horizontal, Space.m)
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
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.smallStrong)
                .foregroundStyle(Palette.inkSecondary)
            Text("Good evening, Devin")
                .font(.hero)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Needs you

    private var needsYou: some View {
        Panel {
            PanelHeader(title: "Needs you", subtitle: "3 things across 2 plans", symbol: "bell.fill", tint: .planner)
                .padding(.bottom, Space.s)

            if let trip {
                ActionRow(symbol: "ticket.fill", tint: .activities,
                          title: "Pick things to do",
                          detail: "\(trip.name) · nobody has voted yet") { model.open(planID: trip.id) }
                Hairline(inset: 56)
            }
            if let car {
                ActionRow(symbol: "calendar", tint: .dates,
                          title: "Book the dealer visit",
                          detail: "\(car.name) · Mom wants to talk to someone first") { model.open(planID: car.id) }
                Hairline(inset: 56)
            }
            ActionRow(symbol: ChatSource.instagram.symbol, tint: ChatSource.instagram.tint,
                      title: "\(model.pendingShared.count) links shared with you",
                      detail: "Maya, Jordan, and Sam · add them to a plan") { model.tab = .shared }
        }
    }

    // MARK: Start a plan

    private var startPlan: some View {
        Panel(padding: 0) {
            Text("Start a plan")
                .font(.heading)
                .foregroundStyle(Palette.ink)
                .padding([.horizontal, .top], Space.m)
                .padding(.bottom, Space.m)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    template("Trip", "airplane", .flights)
                    template("Big purchase", "car.fill", .car)
                    template("Dinner", "fork.knife", .stays)
                    template("Event", "ticket.fill", .activities)
                    template("Gift", "gift.fill", .dates)
                }
                .padding(.horizontal, Space.m)
            }
            .padding(.bottom, Space.m)
        }
    }

    private func template(_ title: String, _ symbol: String, _ tint: Tint) -> some View {
        Button { showNewPlan = true } label: {
            VStack(alignment: .leading, spacing: Space.l) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint.strong)
                Text(title)
                    .font(.bodyStrong)
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 112, height: 112, alignment: .topLeading)
            .padding(Space.m)
            .frame(width: 112 + Space.m * 2, alignment: .leading)
            .background(tint.soft, in: .rect(cornerRadius: Radius.m, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Start a \(title) plan")
    }

    // MARK: Latest from chats

    private var latest: some View {
        Panel {
            PanelHeader(title: "From your chats", subtitle: "Latest Planner replies", symbol: "bubble.left.and.bubble.right.fill", tint: .neutral)
                .padding(.bottom, Space.m)
            ForEach(Array(model.plans.enumerated()), id: \.element.id) { index, plan in
                if let post = plan.messages.last(where: { if case .planner = $0.body { true } else { false } }),
                   case .planner(let p) = post.body {
                    Button { model.open(planID: plan.id) } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack {
                                AppPill(source: plan.source)
                                Text(plan.chatName).font(.smallStrong).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(post.time).font(.small).foregroundStyle(Palette.inkSecondary)
                            }
                            Text(p.text)
                                .font(.bodyRegular)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, Space.m)
                    }
                    .buttonStyle(.pressable)
                    if index < model.plans.count - 1 { Hairline() }
                }
            }
        }
    }
}

// MARK: - Up next hero

private struct UpNextCard: View {
    var plan: Plan
    var action: () -> Void

    private var daysAway: Int {
        let start = DateComponents(calendar: .current, year: 2027, month: 3, day: 26).date ?? .now
        return max(0, Calendar.current.dateComponents([.day], from: .now, to: start).day ?? 0)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Label("Up next", systemImage: "airplane")
                        .font(.smallStrong)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    AvatarStack(members: plan.members, size: 28)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(plan.name).font(.heading).foregroundStyle(.white)
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(daysAway)").font(.hero).figure().foregroundStyle(.white)
                        Text("days to go · Mar 26").font(.bodyRegular).foregroundStyle(.white.opacity(0.85))
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: 4) {
                        ForEach(0..<plan.decisions.count, id: \.self) { i in
                            Capsule().fill(.white.opacity(i < plan.decidedCount ? 1 : 0.25)).frame(height: 4)
                        }
                    }
                    HStack {
                        Text("\(plan.decidedCount) of \(plan.decisions.count) decided")
                            .font(.small).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(plan.nextStep).font(.smallStrong).foregroundStyle(.white)
                        Image(systemName: "chevron.right").font(.small).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accent, in: .rect(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the plan")
    }
}

/// Row with a colored tile, used for to-dos and settings-like lists.
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
                    Text(title).font(.bodyStrong).foregroundStyle(Palette.ink)
                    Text(detail).font(.small).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right").font(.small).foregroundStyle(Palette.inkFaint)
            }
            .padding(.vertical, Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}
