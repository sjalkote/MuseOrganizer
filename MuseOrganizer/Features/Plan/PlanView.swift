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
            HStack {
                SourceLabel(source: plan.source, chatName: plan.chatName)
                Spacer(minLength: Space.s)
                FolderButton(plan: plan)
            }
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
        .accessibilityElement(children: .contain)
    }
}

/// Compact two-column grid of what the group has and hasn't decided.
struct DecisionList: View {
    var decisions: [Decision]
    var note: String? = nil

    private let columns = [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LazyVGrid(columns: columns, spacing: Space.s) {
                ForEach(decisions) { d in
                    HStack(spacing: Space.s) {
                        TintTile(symbol: d.symbol, tint: d.tint, size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(d.title).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                                Spacer(minLength: 0)
                                statusMark(d)
                            }
                            Text(value(d)).font(.smallStrong).foregroundStyle(Palette.ink).lineLimit(1)
                        }
                    }
                    .padding(Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.fill.opacity(0.7), in: .rect(cornerRadius: Radius.s + 2, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(d.title): \(value(d)), \(stateName(d))")
                }
            }
            if let note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.small)
                    .foregroundStyle(Palette.caution)
            }
        }
    }

    /// Short value for the tile: the decided value, or what's happening.
    private func value(_ d: Decision) -> String {
        switch d.state {
        case .decided(let s): s
        case .voting: "Voting now"
        case .open: "Not started"
        }
    }

    private func stateName(_ d: Decision) -> String {
        switch d.state {
        case .decided: "decided"
        case .voting(let s): "voting, \(s)"
        case .open(let s): "open, \(s)"
        }
    }

    @ViewBuilder private func statusMark(_ d: Decision) -> some View {
        switch d.state {
        case .decided:
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.positive)
        case .voting:
            Circle().fill(Palette.accent).frame(width: 7, height: 7)
        case .open:
            Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.5).frame(width: 7, height: 7)
        }
    }
}
