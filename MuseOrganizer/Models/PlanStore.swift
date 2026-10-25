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
    /// What the backend searches for this trip's live options.
    var tripQuery: TripQuery?
    /// What Muse watches for a decision plan (the car's market price).
    var watchRequest: WatchRequest?
    /// The message that started it ("@Muse find flights from Austin, 4 of us, $2,500 each"). Muse reads it to pick the plan's tabs.
    var request: String
    /// Tabs Muse chose for this plan. Nil until the backend answers, and the keyword rules stand in.
    var museSetup: PlanSetup? = nil

    // Live planner state
    var plannerStatus: String?        // "Searching Google Hotels…"
    var planUpdated = false           // dot on the Plan tab after a reply

    let creditBudget = 25
    var creditsUsed: Int { steps.reduce(0) { $0 + $1.credits } }
    var decidedCount: Int { decisions.filter(\.isDecided).count }

    init(id: String, name: String, kind: PlanKind, source: ChatSource, chatName: String, members: [Member],
         decisions: [Decision], nextStep: String, messages: [Message], options: [BoardOption] = [],
         itinerary: [ItineraryDay] = [], leaseOptions: [LeaseOption] = [], steps: [AgentStep],
         sources: [SourceRef], unread: Int, tripQuery: TripQuery? = nil, watchRequest: WatchRequest? = nil,
         request: String = "") {
        self.id = id; self.name = name; self.kind = kind; self.source = source; self.chatName = chatName
        self.members = members; self.decisions = decisions; self.nextStep = nextStep; self.messages = messages
        self.options = options; self.itinerary = itinerary; self.leaseOptions = leaseOptions
        self.steps = steps; self.sources = sources; self.unread = unread
        self.tripQuery = tripQuery; self.watchRequest = watchRequest; self.request = request
    }

    func member(_ id: String) -> Member? { members.first { $0.id == id } }

    /// The decided value of a checklist item ("Dates" → "Mar 26 – Apr 4").
    func decided(_ title: String) -> String? {
        guard case .decided(let value) = decisions.first(where: { $0.title == title })?.state else { return nil }
        return value
    }

    func decision(for category: OptionCategory) -> Decision? {
        decisions.first { $0.title == category.rawValue }
    }

    /// Add places or prices a chat search just found, without clearing options already on the plan.
    func addFound(_ live: [HuddleAPI.Board.Option], listID: String) {
        let known = Set(options.map(\.title))
        for o in live where !known.contains(o.title) {
            let category: OptionCategory = switch o.category {
            case "flights": .flights
            case "stays": .stays
            default: .activities
            }
            options.append(BoardOption(
                category: category, title: o.title, detail: o.detail,
                price: o.price.map(Money.format) ?? (o.priceLabel ?? ""), unit: o.unit, tradeoff: o.tradeoff,
                source: o.source, fetched: "just now", upVotes: 0, downVotes: 0,
                watchID: o.watchId, listID: listID, link: o.link.flatMap(URL.init(string:))
            ))
        }
    }

    /// Swap in live options from the backend. Links people shared stay; votes start fresh on new options.
    func replaceOptions(with live: [HuddleAPI.Board.Option]) {
        let shared = options.filter { $0.sharedBy != nil }
        options = live.map { o in
            let category: OptionCategory = switch o.category {
            case "flights": .flights
            case "stays": .stays
            default: .activities
            }
            return BoardOption(
                category: category, title: o.title, detail: o.detail,
                price: o.price.map(Money.format) ?? (o.priceLabel ?? ""), unit: o.unit, tradeoff: o.tradeoff,
                source: o.source, fetched: "just now", upVotes: 0, downVotes: 0,
                watchID: o.watchId, link: o.link.flatMap(URL.init(string:))
            )
        } + shared
    }

    var lastMessagePreview: String {
        guard let m = messages.last else { return "" }
        let who = m.senderID == "planner" ? "Muse" : (member(m.senderID)?.firstName ?? "")
        switch m.body {
        case .text(let t): return "\(who): \(t)"
        case .planner(let p): return "Muse: \(p.text)"
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
        if trimmed.localizedCaseInsensitiveContains("@planner") || trimmed.localizedCaseInsensitiveContains("@muse") {
            Task { await runPlanner(for: trimmed.lowercased()) }
        }
    }

    /// Muse answers from the plan's live searches and price watches. Without a backend, a scripted demo reply.
    private func runPlanner(for prompt: String) async {
        if let api = HuddleAPI.configured {
            withAnimation(Motion.smooth) { plannerStatus = "Muse is searching…" }
            let started = Date.now
            let text: String
            do {
                let answer = try await api.ask(planID: id, question: prompt, name: name, kind: kindName)
                text = answer.text
                if !answer.options.isEmpty {
                    if let list = answer.list {
                        ensureTab(list.id, title: list.title, kind: ShownTab.Kind(rawValue: list.kind) ?? .options)
                        addFound(answer.options, listID: list.id)
                    } else {
                        addFound(answer.options, listID: tabs.first { $0.kind == .options }?.id ?? "places")
                    }
                    planUpdated = true
                }
            } catch {
                text = "I couldn't reach the search just now (\(error.localizedDescription)). Try again in a minute."
            }
            let seconds = Date.now.timeIntervalSince(started)
            withAnimation(Motion.smooth) {
                plannerStatus = nil
                steps.append(AgentStep(tool: "Answer in the thread", detail: prompt, engine: "SerpApi", duration: seconds, credits: 1))
                messages.append(Message(senderID: "planner", body: .planner(PlannerPost(
                    text: text, trace: ["Muse · \(seconds.formatted(.number.precision(.fractionLength(1))))s", "Added to the plan"]
                )), time: Self.now()))
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        let script: Script
        switch kind {
        case .trip: script = tripScript(prompt)
        case .decision: script = carScript()
        case .gathering, .general: script = generalScript()
        }
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
                    ], action: "Vote in NxT"),
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
                ], action: "Vote in NxT"),
                trace: ["Google Maps · 1.4s"]
            ),
            option: BoardOption(category: .activities, title: "Sumo morning practice", detail: "Ryogoku · 2.5 hours · English guide", price: "$85", unit: "per person", tradeoff: "Up close and unforgettable. 7:30 AM start.", source: "Google Maps", fetched: "just now", upVotes: 0, downVotes: 0)
        )
    }

    private func generalScript() -> Script {
        Script(
            steps: [
                Step(status: "Reading the thread…", record: AgentStep(tool: "Read the thread", detail: name, engine: "Muse Spark", duration: 0.4, credits: 1)),
            ],
            post: PlannerPost(text: "I'll put prices in a Sheet and the plan itself in a Doc."),
            option: nil
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
             steps: Mock.tripSteps, sources: Mock.tripSources, unread: 2, tripQuery: Mock.japanQuery,
             request: "@Muse can you find flights from Austin? Mar 26 – Apr 4, 4 of us, $2,500 each"),
        Plan(id: "car", name: "Our next car", kind: .decision, source: .imessage, chatName: "Family",
             members: Mock.familyMembers, decisions: Mock.carDecisions, nextStep: "Book a dealer visit before July",
             messages: Mock.carMessages, leaseOptions: Mock.leaseOptions,
             steps: Mock.carSteps, sources: Mock.carSources, unread: 1, watchRequest: Mock.carWatch,
             request: "@Muse should we buy out the RAV4 lease or get something new?"),
        Plan(id: "dinner", name: "Bea's birthday dinner", kind: .gathering, source: .instagram, chatName: "Roomies",
             members: Mock.roommates, decisions: Mock.dinnerDecisions, nextStep: "Vote on a place by Thursday",
             messages: Mock.dinnerMessages, options: Mock.dinnerOptions,
             steps: Mock.dinnerSteps, sources: [], unread: 3,
             request: "@Muse where should we go for Bea's birthday dinner Friday? 6 of us, $40 each, one vegan, near Allston"),
        Plan(id: "movie", name: "Friday movie night", kind: .general, source: .imessage, chatName: "Friday crew",
             members: [Mock.me, Mock.maya], decisions: Mock.movieDecisions, nextStep: "Pick a theater",
             messages: Mock.movieMessages, steps: [], sources: [], unread: 0),
    ]

    enum AppTab: Hashable { case home, plans, messages }

    var workspaceService: WorkspaceService = WorkspaceServices.makeDefault()
    /// Muse's price watch across every plan.
    let priceWatch = PriceWatchCenter()

    /// Record that a folder was shared into the group's chat, the way the Planner's posts appear there.
    func shareWorkspace(of plan: Plan) {
        guard var ws = plan.workspace else { return }
        ws.sharedTo = plan.chatName
        plan.workspace = ws
        plan.messages.append(Message(senderID: "planner", body: .planner(PlannerPost(
            text: "The \(ws.folderName) folder is ready: budget, itinerary, and everything we researched.",
            card: .init(title: "Plan folder · \(ws.files.count) files", rows: ws.files.prefix(3).map {
                .init(label: $0.name, detail: $0.kind.label, value: "")
            }, action: "Open folder"),
            trace: ["Shared by link · anyone in \(plan.chatName) can view"]
        )), time: Plan.now()))
    }
    var tab: AppTab = .home
    var plansPath: [String] = []
    var messagesPath: [String] = []
    /// Messages shows group chats or, flipped, what people shared in from Instagram and WhatsApp.
    var messagesShowsShared = false

    /// Unread messages across every group, for the Messages tab badge.
    var unreadCount: Int { plans.reduce(0) { $0 + $1.unread } }

    /// Links and messages shared in from Instagram, WhatsApp, Safari (via the share extension), newest first.
    var shared: [SharedItem] = []

    init() {
        reloadShared()
        publishSnapshots()
    }

    func addPlan(name: String, source: ChatSource, chat: String) {
        let plan = Plan(
            id: UUID().uuidString, name: name, kind: .general, source: source, chatName: chat,
            members: [Mock.me],
            decisions: [Decision(title: "Plan", symbol: "sparkles", tint: .activities, state: .open(name))],
            nextStep: "Build a plan folder when you're ready",
            messages: [Message(senderID: Mock.me.id, body: .text(name), time: Plan.now())],
            steps: [], sources: [], unread: 0
        )
        plans.insert(plan, at: 0)
        publishSnapshots()
        open(planID: plan.id)
    }

    func plan(_ id: String) -> Plan? { plans.first { $0.id == id } }

    func open(planID: String) {
        guard plan(planID) != nil else { return }
        tab = .plans
        plansPath = [planID]
    }

    /// Jump to a group's conversation in Messages.
    func openThread(planID: String) {
        guard plan(planID) != nil else { return }
        tab = .messages
        messagesPath = [planID]
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
            price: "—", unit: "Muse will price it", tradeoff: item.note.isEmpty ? "Added from a shared link." : item.note,
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
        let opts: [PlanSnapshot.Option]
        switch kind {
        case .trip:
            opts = options.filter { $0.category == .flights }.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.detail, price: $0.price, category: $0.category.rawValue, votes: $0.upVotes)
            }
        case .decision:
            opts = leaseOptions.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.totalLabel, price: "\($0.monthly)/mo", category: "Options", votes: $0.votes.count)
            }
        case .gathering, .general:
            opts = options.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.detail, price: $0.price, category: $0.category.rawValue, votes: $0.upVotes)
            }
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
