import SwiftUI

/// Group chat: every member plus Muse. Muse's messages may carry result cards.
struct GroupView: View {
    let group: GroupRef

    @State private var messages: [Message] = []
    @State private var members: [String: String] = [:]
    @State private var draft = ""
    @State private var running = false
    @State private var showPrivate = false
    @State private var error: String?

    var body: some View {
        ChatScroll(messages: messages, me: group.memberId, names: members) { option in
            Task {
                do {
                    _ = try await API.explain(group.sessionId, group.memberId, option: option.name)
                    showPrivate = true
                } catch { self.error = error.localizedDescription }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Button {
                    Task { await act { messages = try await API.run(group.sessionId) } }
                } label: {
                    Label(running ? "Muse is searching…" : "Find options", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                Composer(placeholder: "Message the group", text: $draft) { text in
                    await act { messages = try await API.say(group.sessionId, group.memberId, text) }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        // ponytail: 2 s polling until real-time sync lands in milestone 4.
        .task {
            while !Task.isCancelled {
                if let info = try? await API.info(group.sessionId) { members = info.members }
                if let m = try? await API.group(group.sessionId) { messages = m }
                try? await Task.sleep(for: .seconds(2))
            }
        }
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

/// One member's private thread with Muse. Nothing here is ever shown in the group.
struct PrivateThreadView: View {
    let group: GroupRef

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        ChatScroll(messages: messages, me: group.memberId, names: [:], onExplain: nil)
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
                    Composer(placeholder: "Tell Muse your budget, must-haves…", text: $draft) { text in
                        do {
                            messages = try await API.tell(group.sessionId, group.memberId, text)
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Muse")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                messages = (try? await API.thread(group.sessionId, group.memberId)) ?? []
                if messages.isEmpty {
                    messages = [Message(author: "muse", text:
                        "Hi \(group.myName)! Tell me your real budget and must-haves. I'll use them to find options, but I'll never share them with the group or say who wanted what.")]
                }
            }
    }
}

// MARK: - Shared pieces

private struct ChatScroll: View {
    let messages: [Message]
    let me: String
    let names: [String: String]
    let onExplain: ((CarOption) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages.indices, id: \.self) { i in
                    Bubble(message: messages[i], mine: messages[i].author == me,
                           name: messages[i].author == "muse" ? "Muse" : names[messages[i].author] ?? "Member")
                    if let cards = messages[i].cards, !cards.isEmpty {
                        CardCarousel(cards: cards, onExplain: onExplain)
                    }
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
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
    let onExplain: ((CarOption) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                    CarCardView(option: card.option, rank: i + 1, onExplain: onExplain)
                        .containerRelativeFrame(.horizontal) { w, _ in w * 0.85 }
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
