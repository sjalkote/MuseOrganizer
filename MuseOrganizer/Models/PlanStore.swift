import SwiftUI

@Observable
final class Plan: Identifiable {
    let id: String
    var name: String
    var kind: PlanKind
    var source: ChatSource
    var chatName: String
    var members: [Member]
    var decisions: [Decision]
    var nextStep: String
    var messages: [Message]
    var options: [BoardOption]
    var itinerary: [ItineraryDay]
    var leaseOptions: [LeaseOption]
    var steps: [AgentStep]
    var sources: [SourceRef]
    var unread: Int

    /// The Google Drive folder built for this plan, once someone builds it.
    var workspace: PlanWorkspace?

    // Live planner state
    var plannerStatus: String?        // "Searching Google Hotels…"
    var planUpdated = false           // dot on the Plan tab after a reply

    let creditBudget = 25
    var creditsUsed: Int { steps.reduce(0) { $0 + $1.credits } }
    var decidedCount: Int { decisions.filter(\.isDecided).count }

    init(id: String, name: String, kind: PlanKind, source: ChatSource, chatName: String, members: [Member],
         decisions: [Decision], nextStep: String, messages: [Message], options: [BoardOption] = [],
         itinerary: [ItineraryDay] = [], leaseOptions: [LeaseOption] = [], steps: [AgentStep],
         sources: [SourceRef], unread: Int) {
        self.id = id; self.name = name; self.kind = kind; self.source = source; self.chatName = chatName
        self.members = members; self.decisions = decisions; self.nextStep = nextStep; self.messages = messages
        self.options = options; self.itinerary = itinerary; self.leaseOptions = leaseOptions
        self.steps = steps; self.sources = sources; self.unread = unread
    }

    func member(_ id: String) -> Member? { members.first { $0.id == id } }

    var lastMessagePreview: String {
        guard let m = messages.last else { return "" }
        let who = m.senderID == "planner" ? "Planner" : (member(m.senderID)?.firstName ?? "")
        switch m.body {
        case .text(let t): return "\(who): \(t)"
        case .planner(let p): return "Planner: \(p.text)"
        case .event(let e): return e
        }
    }

    // MARK: Votes

    func vote(_ id: BoardOption.ID, _ vote: BoardOption.Vote) {
        guard let i = options.firstIndex(where: { $0.id == id }) else { return }
        var o = options[i]
        if o.myVote == .up { o.upVotes -= 1 }
        if o.myVote == .down { o.downVotes -= 1 }
        o.myVote = (o.myVote == vote) ? .none : vote
        if o.myVote == .up { o.upVotes += 1 }
        if o.myVote == .down { o.downVotes += 1 }
        options[i] = o
    }

    // MARK: Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(Message(senderID: Mock.me.id, body: .text(trimmed), time: Self.now()))
        if trimmed.localizedCaseInsensitiveContains("@planner") {
            Task { await runPlanner(for: trimmed.lowercased()) }
        }
    }

    /// Scripted stand-in for the real Muse Spark + SerpApi pipeline.
    private func runPlanner(for prompt: String) async {
        let script = kind == .trip ? tripScript(prompt) : carScript()
        try? await Task.sleep(for: .milliseconds(400))
        for step in script.steps {
            withAnimation(Motion.smooth) { plannerStatus = step.status }
            steps.append(step.record)
            try? await Task.sleep(for: .milliseconds(1200))
        }
        withAnimation(Motion.smooth) {
            plannerStatus = nil
            messages.append(Message(senderID: "planner", body: .planner(script.post), time: Self.now()))
            if let option = script.option {
                let at = options.lastIndex { $0.category == option.category }.map { $0 + 1 } ?? options.count
                options.insert(option, at: at)
                planUpdated = true
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private struct Step { var status: String; var record: AgentStep }
    private struct Script { var steps: [Step]; var post: PlannerPost; var option: BoardOption? }

    private func tripScript(_ p: String) -> Script {
        if p.contains("hotel") || p.contains("kyoto") || p.contains("stay") {
            return Script(
                steps: [
                    Step(status: "Reading the thread…", record: AgentStep(tool: "Read the thread", detail: "Kyoto, 2 nights minimum", engine: "Muse Spark", duration: 0.4, credits: 1)),
                    Step(status: "Searching Google Hotels…", record: AgentStep(tool: "Search stays", detail: "Kyoto · Gion · 4 guests", engine: "SerpApi · google_hotels", duration: 1.9, credits: 1)),
                ],
                post: PlannerPost(
                    text: "Found a ryokan near Gion. It's $36 a night more than the machiya, but breakfast is included.",
                    card: .init(title: "Stays · Kyoto", rows: [
                        .init(label: "Ryokan Yachiyo", detail: "4.7 rating · breakfast included", value: "$250"),
                        .init(label: "Kyoto Machiya House", detail: "4.8 rating · current pick", value: "$214"),
                    ], action: "Vote in Huddle"),
                    trace: ["Google Hotels · 1.9s"]
                ),
                option: BoardOption(category: .stays, title: "Ryokan Yachiyo", detail: "4.7 rating · 2 rooms · breakfast included", price: "$250", unit: "per night", tradeoff: "Pricier, but steps from Gion with breakfast.", source: "Google Hotels", fetched: "just now", upVotes: 0, downVotes: 0)
            )
        }
        return Script(
            steps: [
                Step(status: "Reading the thread…", record: AgentStep(tool: "Read the thread", detail: "Day 3 is open", engine: "Muse Spark", duration: 0.4, credits: 1)),
                Step(status: "Searching Google Maps…", record: AgentStep(tool: "Find things to do", detail: "Tokyo · late March", engine: "SerpApi · google_maps", duration: 1.4, credits: 1)),
            ],
            post: PlannerPost(
                text: "Day 3 is open. A sumo morning practice is the most-saved thing to do in Tokyo in late March.",
                card: .init(title: "Things to do · Day 3", rows: [
                    .init(label: "Sumo morning practice", detail: "Ryogoku · 2.5 hours", value: "$85"),
                ], action: "Vote in Huddle"),
                trace: ["Google Maps · 1.4s"]
            ),
            option: BoardOption(category: .activities, title: "Sumo morning practice", detail: "Ryogoku · 2.5 hours · English guide", price: "$85", unit: "per person", tradeoff: "Up close and unforgettable. 7:30 AM start.", source: "Google Maps", fetched: "just now", upVotes: 0, downVotes: 0)
        )
    }

    private func carScript() -> Script {
        Script(
            steps: [
                Step(status: "Reading the thread…", record: AgentStep(tool: "Read the thread", detail: "Priya takes the car to college", engine: "Muse Spark", duration: 0.4, credits: 1)),
                Step(status: "Checking used RAV4 prices…", record: AgentStep(tool: "Price check", detail: "Certified pre-owned · Austin", engine: "SerpApi · google_shopping", duration: 2.0, credits: 1)),
                Step(status: "Re-running the numbers…", record: AgentStep(tool: "Cost model", detail: "Updated for 3 more years", engine: "Calculator", duration: 0.5, credits: 0)),
            ],
            post: PlannerPost(
                text: "If Priya takes the RAV4 to college, buying out still saves about $3,100 over three years. A dealer visit before July locks in the 5.9% rate.",
                trace: ["Google Shopping · 2.0s", "Cost model"]
            ),
            option: nil
        )
    }

    static func now() -> String { Date.now.formatted(date: .omitted, time: .shortened) }
}

@Observable
final class AppModel {
    var plans: [Plan] = [
        Plan(id: "japan", name: "Japan Trip 2027", kind: .trip, source: .whatsapp, chatName: "Japan crew",
             members: Mock.tripMembers, decisions: Mock.tripDecisions, nextStep: "Book flights by Friday",
             messages: Mock.tripMessages, options: Mock.tripOptions, itinerary: Mock.itinerary,
             steps: Mock.tripSteps, sources: Mock.tripSources, unread: 2),
        Plan(id: "car", name: "Our next car", kind: .decision, source: .imessage, chatName: "Family",
             members: Mock.familyMembers, decisions: Mock.carDecisions, nextStep: "Book a dealer visit before July",
             messages: Mock.carMessages, leaseOptions: Mock.leaseOptions,
             steps: Mock.carSteps, sources: Mock.carSources, unread: 1),
    ]

    enum AppTab: Hashable { case home, plans, shared, apps }

    /// Google account used for plan folders (simulated sign-in for now).
    var googleAccount: String?
    var workspaceService: WorkspaceService = WorkspaceServices.makeDefault()

    /// Record that a folder was shared into the group's chat, the way the Planner's posts appear there.
    func shareWorkspace(of plan: Plan) {
        guard var ws = plan.workspace else { return }
        ws.sharedTo = plan.chatName
        plan.workspace = ws
        plan.messages.append(Message(senderID: "planner", body: .planner(PlannerPost(
            text: "The \(ws.folderName) folder is ready: budget, itinerary, and everything we researched.",
            card: .init(title: "Google Drive · \(ws.files.count) files", rows: ws.files.prefix(3).map {
                .init(label: $0.name, detail: $0.kind.label, value: "")
            }, action: "Open folder"),
            trace: ["Shared by link · anyone in \(plan.chatName) can view"]
        )), time: Plan.now()))
    }
    var tab: AppTab = .home
    var plansPath: [String] = []

    /// Links and messages shared in from Instagram, WhatsApp, Safari (via the share extension), newest first.
    var shared: [SharedItem] = []

    init() {
        reloadShared()
        publishSnapshots()
    }

    func plan(_ id: String) -> Plan? { plans.first { $0.id == id } }

    func open(planID: String) {
        guard plan(planID) != nil else { return }
        tab = .plans
        plansPath = [planID]
    }

    func handle(_ url: URL) {
        if let id = DeepLink.planID(from: url) { open(planID: id) }
    }

    // MARK: Shared items

    func reloadShared() {
        let fromExtension = SharedStore.items()
        let known = Set(fromExtension.map(\.id))
        shared = fromExtension + Mock.sharedItems.filter { !known.contains($0.id) }
    }

    var pendingShared: [SharedItem] { shared.filter { !$0.added } }

    /// Turn a shared link into an option the group can vote on.
    func add(_ item: SharedItem) {
        guard let i = shared.firstIndex(where: { $0.id == item.id }),
              let plan = plan(item.planID ?? "japan") else { return }
        let category = OptionCategory(rawValue: item.category ?? "") ?? .activities
        let option = BoardOption(
            category: category, title: item.title,
            detail: "Shared by \(item.sharedBy) from \(item.source)",
            price: "—", unit: "Planner will price it", tradeoff: item.note.isEmpty ? "Added from a shared link." : item.note,
            source: item.source, fetched: "just now", upVotes: 0, downVotes: 0,
            sharedBy: item.sharedBy, sharedFrom: ChatSource(rawValue: item.source)
        )
        withAnimation(Motion.smooth) {
            let at = plan.options.lastIndex { $0.category == category }.map { $0 + 1 } ?? plan.options.count
            plan.options.insert(option, at: at)
            plan.planUpdated = true
            shared[i].added = true
        }
        SharedStore.update(shared[i])
        publishSnapshots()
    }

    // MARK: Extensions

    /// Write plan snapshots to the App Group so the iMessage app and share extension can show them.
    func publishSnapshots() {
        SharedStore.save(plans: plans.map(\.snapshot))
    }
}

extension Plan {
    var snapshot: PlanSnapshot {
        let opts: [PlanSnapshot.Option] = kind == .trip
            ? options.filter { $0.category == .flights }.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.detail, price: $0.price, category: $0.category.rawValue, votes: $0.upVotes)
              }
            : leaseOptions.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.totalLabel, price: "\($0.monthly)/mo", category: "Options", votes: $0.votes.count)
              }
        return PlanSnapshot(id: id, name: name, chatName: chatName, source: source.rawValue,
                            decided: decidedCount, total: decisions.count, nextStep: nextStep,
                            memberNames: members.map(\.firstName), options: opts)
    }

    /// The update Huddle posts back into the group chat.
    var chatUpdate: String {
        var lines = ["\(name): \(decidedCount) of \(decisions.count) decided"]
        if kind == .trip, let top = options.filter({ $0.category == .flights }).max(by: { $0.upVotes < $1.upVotes }) {
            lines.append("Flights: \(top.title) leads at \(top.price) (\(top.upVotes) votes)")
        }
        if kind == .decision, let top = leaseOptions.first(where: \.isRecommended) {
            lines.append("Leading: \(top.title), \(top.monthly)/mo")
        }
        lines.append("Next: \(nextStep)")
        lines.append("Vote: \(DeepLink.web(id).absoluteString)")
        return lines.joined(separator: "\n")
    }
}
