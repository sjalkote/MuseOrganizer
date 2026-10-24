import SwiftUI

/// Group chat: every member plus Muse. Muse's messages may carry result cards to vote on.
struct GroupView: View {
    let group: GroupRef

    @State private var live: GroupState?
    @State private var draft = ""
    @State private var running = false
    @State private var showPrivate = false
    @State private var comparing: [CarOption]?
    @State private var error: String?

    var body: some View {
        ChatScroll(messages: live?.group ?? [], me: group.memberId, names: live?.members ?? [:],
                   voting: live.map { Voting(state: $0, onVote: vote) },
                   thinking: running ? "Muse is searching…" : nil,
                   onCompare: { comparing = $0 }) { option in
            Task {
                do {
                    _ = try await API.explain(group.sessionId, group.memberId, option: option.name)
                    showPrivate = true
                } catch { self.error = error.localizedDescription }
            }
        }
        .safeAreaInset(edge: .top) {
            if let live {
                MembersBar(state: live).background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let live {
                    VoteStatus(state: live)
                }
                Button {
                    Task { await act { _ = try await API.run(group.sessionId) } }
                } label: {
                    Label(live?.tally.isEmpty == false ? "Search again" : "Find options", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(running)
                Composer(placeholder: "Message the group", text: $draft) { text in
                    await act { _ = try await API.say(group.sessionId, group.memberId, text) }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "Help us decide on Huddle! Join \"\(group.title)\" with invite code \(group.sessionId)") {
                    Label("Invite", systemImage: "person.badge.plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Private with Muse", systemImage: "lock.fill") { showPrivate = true }
            }
        }
        .sheet(isPresented: $showPrivate) {
            NavigationStack {
                PrivateThreadView(group: group)
                    .toolbar { Button("Done") { showPrivate = false } }
            }
        }
        .sheet(item: Binding(get: { comparing.map(CompareSet.init) }, set: { comparing = $0?.options })) { set in
            NavigationStack {
                CompareView(options: set.options, tally: live?.tally ?? [:])
                    .toolbar { Button("Done") { comparing = nil } }
            }
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.selection, trigger: live?.myVote)
        .sensoryFeedback(.success, trigger: live?.winner)
        // The stream fires once on connect and again on every change, from any member's device.
        .task { await API.listen(group.sessionId) { await refresh() } }
    }

    private func refresh() async {
        do {
            let s = try await API.state(group.sessionId, group.memberId)
            withAnimation(.snappy) { live = s }
        } catch { self.error = error.localizedDescription }
    }

    private func vote(_ option: String) {
        Task { await act { live = try await API.vote(group.sessionId, group.memberId, option: option) } }
    }

    private func act(_ work: () async throws -> Void) async {
        running = true
        defer { running = false }
        do {
            try await work()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// What a card needs to show voting: live counts, my vote, and the winner once everyone has voted.
struct Voting {
    let state: GroupState
    let onVote: (String) -> Void
}

private struct CompareSet: Identifiable {
    let options: [CarOption]
    var id: String { options.map(\.name).joined() }
}

/// Who's in the group and who has told Muse their limits (never what they said).
private struct MembersBar: View {
    let state: GroupState

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(state.members.sorted(by: { $0.value < $1.value }), id: \.key) { _, name in
                        Avatar(name: name, done: state.shared.contains(name))
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            Text(state.shared.count == state.members.count
                 ? "Everyone has told Muse their limits privately"
                 : "\(state.shared.count) of \(state.members.count) have told Muse their limits privately")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct Avatar: View {
    let name: String
    var done = false

    private static let colors: [Color] = [.blue, .pink, .orange, .teal, .indigo, .green, .purple]

    var body: some View {
        VStack(spacing: 2) {
            Text(String(name.prefix(1)).uppercased())
                .font(.headline).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Self.colors[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count].gradient, in: .circle)
                .overlay(alignment: .bottomTrailing) {
                    if done {
                        Image(systemName: "lock.circle.fill")
                            .font(.caption).foregroundStyle(.white, .green)
                            .offset(x: 3, y: 3)
                    }
                }
            Text(name).font(.caption2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done ? "\(name), has shared limits with Muse" : name)
    }
}

private struct VoteStatus: View {
    let state: GroupState

    var body: some View {
        if let winner = state.winner {
            Label("\(winner) won the vote", systemImage: "trophy.fill")
                .font(.subheadline.bold()).foregroundStyle(.orange)
        } else if !state.voted.isEmpty {
            Text("Voted: \(state.voted.joined(separator: ", ")) · \(state.voted.count) of \(state.members.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One member's private thread with Muse. Nothing here is ever shown in the group.
struct PrivateThreadView: View {
    let group: GroupRef

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        ChatScroll(messages: messages, me: group.memberId, names: [:], voting: nil,
                   thinking: sending ? "Muse is thinking…" : nil, onCompare: nil, onExplain: nil,
                   onReply: { reply in Task { await send(reply) } })
            .safeAreaInset(edge: .top) {
                Label("Only you and Muse see this", systemImage: "lock.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.bar)
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Composer(placeholder: "Tell Muse your budget, must-haves…", text: $draft) { await send($0) }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Muse")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await API.listen(group.sessionId) {
                    guard let m = try? await API.thread(group.sessionId, group.memberId) else { return }
                    withAnimation(.snappy) {
                        messages = m.isEmpty ? [Message(author: "muse", text:
                            "Hi \(group.myName)! Tell me your real budget and must-haves. I'll use them to find options, but I'll never share them with the group or say who wanted what.")] : m
                    }
                }
            }
    }

    private func send(_ text: String) async {
        sending = true
        defer { sending = false }
        do {
            messages = try await API.tell(group.sessionId, group.memberId, text)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Shared pieces

private struct ChatScroll: View {
    let messages: [Message]
    let me: String
    let names: [String: String]
    let voting: Voting?
    var thinking: String? = nil
    let onCompare: (([CarOption]) -> Void)?
    let onExplain: ((CarOption) -> Void)?
    var onReply: ((String) -> Void)? = nil

    var body: some View {
        // Only the newest set of cards stays interactive; older result sets collapse to their text.
        let lastCards = messages.lastIndex { !($0.cards ?? []).isEmpty }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages.indices, id: \.self) { i in
                    let m = messages[i]
                    Bubble(message: m, mine: m.author == me,
                           name: m.author == "muse" ? "Muse" : names[m.author] ?? "Member")
                    if i == lastCards, let cards = m.cards {
                        CardCarousel(cards: cards, voting: voting, onExplain: onExplain)
                        if cards.count > 1, let onCompare {
                            Button("Compare side by side", systemImage: "tablecells") {
                                onCompare(cards.map(\.option))
                            }
                            .font(.subheadline)
                        }
                    }
                    if i == messages.count - 1, m.author == "muse", let replies = m.replies, let onReply, thinking == nil {
                        QuickReplies(replies: replies, onReply: onReply)
                    }
                }
                if let thinking {
                    Label(thinking, systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(.purple)
                        .symbolEffect(.pulse)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.purple.opacity(0.08), in: .rect(cornerRadius: 16))
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }
}

private struct QuickReplies: View {
    let replies: [String]
    let onReply: (String) -> Void

    var body: some View {
        HStack {
            ForEach(replies, id: \.self) { r in
                Button(r) { onReply(r) }
                    .buttonStyle(.bordered)
                    .tint(.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Bubble: View {
    let message: Message
    let mine: Bool
    let name: String

    var body: some View {
        let muse = message.author == "muse"
        HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if !mine {
                    Label(name, systemImage: muse ? "sparkles" : "person.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muse ? Color.purple : .secondary)
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Color.accentColor : muse ? Color.purple.opacity(0.12) : Color(.secondarySystemBackground),
                                in: .rect(cornerRadius: 16))
                    .foregroundStyle(mine ? .white : .primary)
            }
            if !mine { Spacer(minLength: 48) }
        }
    }
}

private struct CardCarousel: View {
    let cards: [Card]
    let voting: Voting?
    let onExplain: ((CarOption) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                    CarCardView(option: card.option, rank: i + 1, voting: voting, onExplain: onExplain)
                        .containerRelativeFrame(.horizontal) { w, _ in cards.count == 1 ? w : w * 0.85 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

private struct Composer: View {
    let placeholder: String
    @Binding var text: String
    let send: (String) async -> Void

    @State private var sending = false

    var body: some View {
        HStack {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
            Button("Send", systemImage: "arrow.up.circle.fill") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = ""
                Task {
                    sending = true
                    await send(t)
                    sending = false
                }
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
