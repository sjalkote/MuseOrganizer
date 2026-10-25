import SwiftUI

struct PlanView: View {
    @Bindable var plan: Plan
    @State private var tab: Tab = .plan
    @State private var showActivity = false
    @State private var showShare = false

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
            ToolbarItemGroup(placement: .topBarTrailing) {
                FolderButton(plan: plan)
                Menu("More", systemImage: "ellipsis") {
                    Button("Post update to \(plan.chatName)", systemImage: "arrow.up.message") {
                        if !ChatBridge.open(ChatBridge.composeURL(for: plan.source, text: plan.chatUpdate)) { showShare = true }
                    }
                    if plan.kind == .trip {
                        ShareLink(item: CalendarExport.file(for: plan),
                                  preview: SharePreview("\(plan.name).ics", image: Image(systemName: "calendar"))) {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                    Button("Planner activity", systemImage: "list.bullet.rectangle") { showActivity = true }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [plan.chatUpdate]).presentationDetents([.medium, .large])
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
        VStack(alignment: .leading, spacing: Space.s + 2) {
            HStack(alignment: .center, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(plan.decidedCount) of \(plan.decisions.count)")
                            .font(.heading)
                            .figure()
                            .foregroundStyle(Palette.ink)
                        Text("decided")
                            .font(.small)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    SourceLabel(source: plan.source, chatName: plan.chatName)
                }
                Spacer(minLength: Space.s)
                AvatarStack(members: plan.members, size: 26)
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
