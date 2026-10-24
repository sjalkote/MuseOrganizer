import SwiftUI

/// A mirror of the group's existing chat. Huddle doesn't replace WhatsApp or iMessage:
/// messages here post to the real thread, and the Planner's replies arrive there as cards.
struct ThreadView: View {
    @Bindable var plan: Plan
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        plan.kind == .trip
            ? ["@Planner find a hotel in Kyoto", "@Planner what should we do on Day 3?"]
            : ["@Planner what if Priya takes the car?"]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.xs) {
                    mirrorNote
                        .padding(.bottom, Space.m)
                    Text("Today")
                        .font(.small)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.bottom, Space.s)

                    ForEach(Array(plan.messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? plan.messages[index - 1] : nil
                        let next = index < plan.messages.count - 1 ? plan.messages[index + 1] : nil
                        MessageRow(
                            message: message,
                            sender: plan.member(message.senderID),
                            isFirstInGroup: previous?.senderID != message.senderID,
                            isLastInGroup: next?.senderID != message.senderID,
                            chatSource: plan.source
                        )
                        .id(message.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let status = plan.plannerStatus {
                        HStack(spacing: Space.s) {
                            PlannerLabel(working: true)
                            Text(status)
                                .font(.small)
                                .foregroundStyle(Palette.inkSecondary)
                                .contentTransition(.opacity)
                            Spacer()
                        }
                        .padding(.top, Space.m)
                        .id("status")
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.m)
            }
            .background(Palette.panel)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .onChange(of: plan.messages.count) {
                withAnimation(Motion.smooth) { proxy.scrollTo(plan.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: focused) {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(Motion.smooth) { proxy.scrollTo(plan.messages.last?.id, anchor: .bottom) }
                }
            }
            .onChange(of: plan.plannerStatus) {
                if plan.plannerStatus != nil { withAnimation(Motion.smooth) { proxy.scrollTo("status", anchor: .bottom) } }
            }
        }
    }

    private var mirrorNote: some View {
        HStack(spacing: Space.m) {
            TintTile(symbol: plan.source.symbol, tint: plan.source.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plan.chatName) on \(plan.source.rawValue)")
                    .font(.smallStrong).foregroundStyle(Palette.ink)
                Text("Mirrored here. Messages you send post to \(plan.source.rawValue).")
                    .font(.small).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: Space.s)
            Button("Open") { ChatBridge.open(ChatBridge.openURL(for: plan.source)) }
                .font(.smallStrong)
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Open in \(plan.source.rawValue)")
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.s)
        .padding(.vertical, Space.s)
        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: Space.s) {
            if focused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { draft = s } label: {
                                Text(s.replacingOccurrences(of: "@Planner ", with: ""))
                                    .font(.small)
                                    .foregroundStyle(Palette.accent)
                                    .padding(.horizontal, Space.m)
                                    .frame(minHeight: 36)
                                    .background(Palette.accentFill, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.m)
                }
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: Space.s) {
                Button {
                    if !draft.localizedCaseInsensitiveContains("@planner") { draft = "@Planner " + draft }
                    focused = true
                } label: {
                    Image(systemName: "at")
                        .font(.bodyStrong)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 44, height: 44)
                        .background(Palette.fill, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mention Planner")

                HStack(alignment: .bottom, spacing: 0) {
                    TextField("Message \(plan.chatName)", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.vertical, 12)
                        .padding(.leading, Space.m)
                    if !draft.isEmpty {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.smallStrong)
                                .foregroundStyle(Palette.onAccent)
                                .frame(width: 32, height: 32)
                                .background(Palette.accent, in: .circle)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Send")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minHeight: 44)
                .background(Palette.fill, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)
        }
        .padding(.top, Space.s)
        .background(Palette.panel)
        .animation(Motion.snappy, value: focused)
        .animation(Motion.snappy, value: draft.isEmpty)
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Motion.smooth) { plan.send(draft) }
        draft = ""
    }
}

// MARK: - Message row

private struct MessageRow: View {
    var message: Message
    var sender: Member?
    var isFirstInGroup: Bool
    var isLastInGroup: Bool
    var chatSource: ChatSource

    var body: some View {
        switch message.body {
        case .event(let text):
            Text(text)
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s)

        case .planner(let post):
            PlannerPostView(post: post, time: message.time, chatSource: chatSource)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)

        case .text(let text):
            if sender?.isMe == true {
                HStack {
                    Spacer(minLength: 64)
                    Text(highlighted(text, mine: true))
                        .font(.bodyRegular)
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.accent, in: .rect(cornerRadius: 20, style: .continuous))
                }
                .padding(.top, isFirstInGroup ? Space.s : 0)
                .accessibilityLabel("You: \(text)")
            } else if let sender {
                HStack(alignment: .bottom, spacing: Space.s) {
                    Avatar(member: sender, size: 28).opacity(isLastInGroup ? 1 : 0)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        if isFirstInGroup {
                            Text(sender.firstName)
                                .font(.small)
                                .foregroundStyle(Palette.inkSecondary)
                                .padding(.leading, 14)
                        }
                        Text(highlighted(text, mine: false))
                            .font(.bodyRegular)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Palette.fill, in: .rect(cornerRadius: 20, style: .continuous))
                    }
                    Spacer(minLength: 48)
                }
                .padding(.top, isFirstInGroup ? Space.s : 0)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(sender.name): \(text)")
            }
        }
    }

    private func highlighted(_ text: String, mine: Bool) -> AttributedString {
        var a = AttributedString(text)
        if let r = a.range(of: "@Planner", options: .caseInsensitive) {
            a[r].font = .body.weight(.semibold)
            if !mine { a[r].foregroundColor = Palette.accent }
        }
        return a
    }
}

/// What the Planner posts into the real group chat: a short reply plus a rich card.
struct PlannerPostView: View {
    var post: PlannerPost
    var time: String
    var chatSource: ChatSource

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                PlannerLabel()
                Spacer()
                Text(time).font(.small).foregroundStyle(Palette.inkSecondary)
            }

            Text(post.text)
                .font(.bodyRegular)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let card = post.card {
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.title)
                        .font(.smallStrong)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.m)
                        .padding(.bottom, Space.xs)
                    ForEach(card.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(.bodyRegular).foregroundStyle(Palette.ink)
                                Text(row.detail).font(.small).foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            Text(row.value).font(.bodyStrong).figure().foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                    }
                    Hairline()
                    HStack {
                        Text(card.action).font(.smallStrong).foregroundStyle(Palette.accent)
                        Spacer()
                        Image(systemName: "chevron.right").font(.small).foregroundStyle(Palette.accent)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 44)
                }
                .background(Palette.background, in: .rect(cornerRadius: Radius.m, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Palette.separator))
                .accessibilityElement(children: .combine)
            }

            if !post.trace.isEmpty {
                Text(post.trace.joined(separator: "  ·  "))
                    .font(.small)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(Space.m)
        .background(Palette.accentFill.opacity(0.6), in: .rect(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
