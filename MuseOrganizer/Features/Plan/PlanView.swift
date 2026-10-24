import SwiftUI

struct PlanView: View {
    @Bindable var plan: Plan
    @State private var tab: Tab = .plan
    @State private var showActivity = false

    enum Tab: String, CaseIterable { case plan = "Plan", thread = "Thread" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab.animation(Motion.smooth)) {
                Text(plan.planUpdated && tab != .plan ? "Plan  •" : "Plan").tag(Tab.plan)
                Text(plan.unread > 0 ? "Thread  \(plan.unread)" : "Thread").tag(Tab.thread)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)

            Group {
                switch tab {
                case .plan:
                    Group {
                        if plan.kind == .trip {
                            TripPlanView(plan: plan)
                        } else {
                            CarPlanView(plan: plan) { withAnimation(Motion.smooth) { tab = .thread } }
                        }
                    }
                    .onAppear { plan.planUpdated = false }
                case .thread:
                    ThreadView(plan: plan)
                        .onAppear { plan.unread = 0 }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Planner activity", systemImage: "list.bullet.rectangle") { showActivity = true }
            }
        }
        .sheet(isPresented: $showActivity) {
            ActivitySheet(plan: plan)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// "3 of 5 decided" summary shared by both plan types.
struct PlanHeader: View {
    var plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SourceLabel(source: plan.source, chatName: plan.chatName)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(plan.decidedCount) of \(plan.decisions.count)")
                    .font(.hero)
                    .figure()
                    .foregroundStyle(Palette.ink)
                Text("decided")
                    .font(.bodyRegular)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                AvatarStack(members: plan.members, size: 28)
            }
            DecisionProgress(decided: plan.decidedCount, total: plan.decisions.count)
            HStack(spacing: Space.s) {
                Text("Next")
                    .font(.smallStrong)
                    .foregroundStyle(Palette.accent)
                Text(plan.nextStep)
                    .font(.small)
                    .foregroundStyle(Palette.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Checklist of what the group has and hasn't decided.
struct DecisionList: View {
    var decisions: [Decision]
    var note: (Decision) -> String? = { _ in nil }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(decisions.enumerated()), id: \.element.id) { index, d in
                HStack(alignment: .top, spacing: Space.m) {
                    TintTile(symbol: d.symbol, tint: d.tint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.bodyRegular).foregroundStyle(Palette.ink)
                        Text(detail(d)).font(.small).foregroundStyle(Palette.inkSecondary)
                        if let note = note(d) {
                            Label(note, systemImage: "exclamationmark.triangle")
                                .font(.small)
                                .foregroundStyle(Palette.caution)
                                .padding(.top, Space.xs)
                        }
                    }
                    Spacer()
                    status(d)
                        .padding(.top, 10)
                }
                .padding(.vertical, Space.m)
                .accessibilityElement(children: .combine)
                if index < decisions.count - 1 {
                    Hairline(inset: 56)
                }
            }
        }
    }

    private func detail(_ d: Decision) -> String {
        switch d.state {
        case .decided(let s), .voting(let s), .open(let s): s
        }
    }

    @ViewBuilder private func status(_ d: Decision) -> some View {
        switch d.state {
        case .decided:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.positive)
                .accessibilityLabel("Decided")
        case .voting:
            Text("Voting").font(.smallStrong).foregroundStyle(Palette.accent)
        case .open:
            Text("Open").font(.smallStrong).foregroundStyle(Palette.inkSecondary)
        }
    }
}
