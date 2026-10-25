import SwiftUI

/// Every group's conversation in one inbox, like Instagram's DMs. Muse's replies live here,
/// so the plan screen can stay about the plan.
struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var conversations: [Plan] {
        let all = model.plans.sorted { ($0.unread, $0.messages.count) > ($1.unread, $1.messages.count) }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.chatName.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)
                || $0.members.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.messagesPath) {
            VStack(spacing: 0) {
                Picker("Show", selection: $model.messagesShowsShared.animation(Motion.smooth)) {
                    Text("Chats").tag(false)
                    Text(model.pendingShared.isEmpty ? "Shared" : "Shared · \(model.pendingShared.count)").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.s)

                if model.messagesShowsShared {
                    SharedView(embedded: true)
                } else {
                    List {
                        ForEach(conversations) { plan in
                            NavigationLink(value: plan.id) { ConversationRow(plan: plan) }
                                .listRowBackground(Palette.canvas)
                                .listRowSeparatorTint(Palette.separator)
                        }
                        if conversations.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .listRowBackground(Palette.canvas)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $query, prompt: "Search chats and people")
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Messages")
            .navigationDestination(for: String.self) { id in
                if let plan = model.plan(id) { ConversationView(plan: plan) }
            }
        }
    }
}

/// One chat in the inbox: who's in it, the last thing said, and whether it's new to you.
private struct ConversationRow: View {
    var plan: Plan

    private var lastTime: String { plan.messages.last?.time ?? "" }

    var body: some View {
        HStack(spacing: Space.m) {
            GroupAvatar(plan: plan, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.chatName)
                        .font(plan.unread > 0 ? .bodyStrong : .bodyRegular)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Image(systemName: plan.source.symbol)
                        .font(.caption2)
                        .foregroundStyle(plan.source.tint.strong)
                        .accessibilityLabel(plan.source.rawValue)
                    Spacer(minLength: Space.s)
                    Text(lastTime).font(.caption).foregroundStyle(Palette.inkSecondary)
                }
                HStack(spacing: Space.s) {
                    Text(plan.lastMessagePreview)
                        .font(.small)
                        .foregroundStyle(plan.unread > 0 ? Palette.ink : Palette.inkSecondary)
                        .fontWeight(plan.unread > 0 ? .semibold : .regular)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if plan.unread > 0 {
                        Circle().fill(Palette.accent).frame(width: 9, height: 9)
                            .accessibilityLabel("\(plan.unread) new")
                    }
                }
                Text(plan.name).font(.caption2).foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The group's photo: the plan's cover colors behind the first two members, like a group DM avatar.
struct GroupAvatar: View {
    var plan: Plan
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [plan.cover.colors[1], plan.cover.colors[4], plan.cover.colors[7]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            let others = plan.members.filter { !$0.isMe }
            if others.count >= 2 {
                Avatar(member: others[0], size: size * 0.5)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: -size * 0.13, y: -size * 0.1)
                Avatar(member: others[1], size: size * 0.5)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: size * 0.14, y: size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The thread itself, with a way back to the plan it belongs to.
struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan

    var body: some View {
        ThreadView(plan: plan)
            .onAppear { plan.unread = 0 }
            .navigationTitle(plan.chatName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.open(planID: plan.id)
                    } label: {
                        Label("View plan", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .accessibilityHint("Opens \(plan.name)")
                }
            }
    }
}
