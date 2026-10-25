import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan
    @State private var showActivity = false
    @State private var showShare = false

    var body: some View {
        PlanScreen(plan: plan)
        .onAppear { plan.planUpdated = false }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // The group chat lives in Messages now; this jumps straight to it.
                Button {
                    model.openThread(planID: plan.id)
                } label: {
                    Image(systemName: plan.unread > 0 ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.bubble.right")
                }
                .accessibilityLabel(plan.unread > 0 ? "Messages, \(plan.unread) new" : "Messages")
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
                    Button("What Muse did", systemImage: "list.bullet.rectangle") { showActivity = true }
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
