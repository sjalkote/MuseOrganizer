import SwiftUI

struct PlansView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewPlan = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.plansPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(model.plans) { plan in
                        NavigationLink(value: plan.id) { PlanRow(plan: plan) }
                            .buttonStyle(.pressable)
                    }
                    Label("Mention @Planner in a linked group chat, or share something into Huddle, to start a plan.",
                          systemImage: "info.circle")
                        .font(.small)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Space.s)
                        .padding(.top, Space.s)
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.canvas)
            .navigationTitle("Plans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New plan", systemImage: "plus") { showNewPlan = true }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let plan = model.plan(id) { PlanView(plan: plan) }
            }
            .sheet(isPresented: $showNewPlan) {
                NewPlanSheet {
                    showNewPlan = false
                    model.plansPath = ["japan"]
                }
            }
        }
    }
}

private struct PlanRow: View {
    var plan: Plan

    private var tint: Tint { plan.kind == .trip ? .flights : .car }
    private var symbol: String { plan.kind == .trip ? "airplane" : "car.fill" }

    var body: some View {
        Panel(padding: 0) {
            HStack(spacing: Space.m) {
                TintTile(symbol: symbol, tint: tint, size: 48)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(plan.name).font(.heading).foregroundStyle(Palette.ink)
                    HStack(spacing: Space.s) {
                        AppPill(source: plan.source)
                        Text(plan.chatName).font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
                if plan.unread > 0 {
                    Text("\(plan.unread)")
                        .font(.smallStrong).figure()
                        .foregroundStyle(Palette.onAccent)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Palette.accent, in: .capsule)
                        .accessibilityLabel("\(plan.unread) new messages")
                }
            }
            .padding(Space.m)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("\(plan.decidedCount) of \(plan.decisions.count) decided")
                        .font(.smallStrong).foregroundStyle(Palette.ink)
                    Spacer()
                    AvatarStack(members: plan.members, size: 24)
                }
                DecisionProgress(decided: plan.decidedCount, total: plan.decisions.count)
                HStack(spacing: Space.s) {
                    Text("Next").font(.smallStrong).foregroundStyle(Palette.accent)
                    Text(plan.nextStep).font(.small).foregroundStyle(Palette.ink)
                }
                .padding(.top, Space.xs)
            }
            .padding(Space.m)
            .background(Palette.fill.opacity(0.6))
        }
        .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the plan")
    }
}

#Preview {
    PlansView().environment(AppModel())
}
