import Messages
import SwiftUI
import UIKit

/// Huddle's iMessage app. Sends a plan as an interactive card; friends tap the card to vote,
/// and each vote updates the same bubble in place (one card per plan, not a stream of messages).
final class MessagesViewController: MSMessagesAppViewController {
    private var host: UIHostingController<MessagesRootView>?

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        render(for: conversation, style: presentationStyle)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        if let conversation = activeConversation { render(for: conversation, style: presentationStyle) }
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        render(for: conversation, style: .expanded)
    }

    private func render(for conversation: MSConversation, style: MSMessagesAppPresentationStyle) {
        let selected = conversation.selectedMessage
        let card = selected.flatMap { PlanCard(url: $0.url) }
        let root = MessagesRootView(
            plans: SharedStore.plans(),
            card: style == .expanded ? card : nil,
            send: { [weak self] plan in self?.send(PlanCard(plan: plan), session: nil) },
            vote: { [weak self] card, optionID in
                var updated = card
                updated.vote(optionID, voter: "You")
                self?.send(updated, session: selected?.session)
            }
        )

        if let host {
            host.rootView = root
        } else {
            let controller = UIHostingController(rootView: root)
            addChild(controller)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: view.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            controller.didMove(toParent: self)
            host = controller
        }
    }

    /// Inserts (or updates, when there's a session) the plan card in the conversation.
    private func send(_ card: PlanCard, session: MSSession?) {
        guard let conversation = activeConversation else { return }
        let message = MSMessage(session: session ?? MSSession())
        let layout = MSMessageTemplateLayout()
        layout.image = card.image()
        layout.caption = card.name
        layout.subcaption = card.subtitle
        layout.trailingSubcaption = "Tap to vote"
        message.layout = layout
        message.url = card.url
        message.summaryText = card.lastAction ?? "Sent \(card.name)"

        conversation.insert(message) { error in
            if let error { print("Huddle: couldn't insert message: \(error)") }
        }
        dismiss()
    }
}

// MARK: - Plan card state, carried in the message URL

/// iMessage apps keep shared state in the message itself, so votes travel with the bubble.
struct PlanCard: Hashable {
    var planID: String
    var name: String
    var decided: Int
    var total: Int
    var options: [Option]
    var lastAction: String?

    struct Option: Hashable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var price: String
        var votes: Int
    }

    init(plan: PlanSnapshot) {
        planID = plan.id
        name = plan.name
        decided = plan.decided
        total = plan.total
        options = plan.options.map { Option(id: $0.id, title: $0.title, detail: $0.detail, price: $0.price, votes: $0.votes) }
    }

    init?(url: URL?) {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = DeepLink.planID(from: url),
              let plan = SharedStore.plans().first(where: { $0.id == id }) else { return nil }
        self.init(plan: plan)
        let items = parts.queryItems ?? []
        for i in options.indices {
            if let v = items.first(where: { $0.name == options[i].id })?.value, let n = Int(v) { options[i].votes = n }
        }
        lastAction = items.first { $0.name == "last" }?.value
    }

    var leader: Option? { options.max { $0.votes < $1.votes } }

    var subtitle: String {
        if let leader { return "\(leader.title) leads · \(leader.votes) votes" }
        return "\(decided) of \(total) decided"
    }

    var url: URL {
        var parts = URLComponents(url: DeepLink.web(planID), resolvingAgainstBaseURL: false)!
        parts.queryItems = options.map { URLQueryItem(name: $0.id, value: "\($0.votes)") }
            + (lastAction.map { [URLQueryItem(name: "last", value: $0)] } ?? [])
        return parts.url!
    }

    mutating func vote(_ optionID: String, voter: String) {
        guard let i = options.firstIndex(where: { $0.id == optionID }) else { return }
        options[i].votes += 1
        lastAction = "\(voter) voted for \(options[i].title)"
    }

    /// Picture shown in the bubble.
    func image() -> UIImage? {
        let renderer = ImageRenderer(content: CardArt(card: self).frame(width: 300, height: 180))
        renderer.scale = 3
        return renderer.uiImage
    }
}
