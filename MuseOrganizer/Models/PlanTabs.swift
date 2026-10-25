import SwiftUI

/// The tabs a plan can show. Which ones appear depends on what the group asked Muse for:
/// a road trip has no Flights tab, a dinner is just places and who's in.
enum PlanTab: String, Identifiable, Hashable {
    case overview, flights, route, gettingThere, stays, todo, places, guests, money, options, numbers, prices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .flights: "Flights"
        case .route: "Route"
        case .gettingThere: "Getting there"
        case .stays: "Stays"
        case .todo: "Do"
        case .places: "Places"
        case .guests: "Who's in"
        case .money: "Money"
        case .options: "Options"
        case .numbers: "Numbers"
        case .prices: "Prices"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles.rectangle.stack"
        case .flights: "airplane"
        case .route: "car.fill"
        case .gettingThere: "tram.fill"
        case .stays: "bed.double.fill"
        case .todo: "ticket.fill"
        case .places: "fork.knife"
        case .guests: "person.2.fill"
        case .money: "dollarsign.circle.fill"
        case .options: "square.grid.2x2.fill"
        case .numbers: "chart.bar.fill"
        case .prices: "chart.line.downtrend.xyaxis"
        }
    }

    var tint: Tint {
        switch self {
        case .flights, .gettingThere: .flights
        case .stays: .stays
        case .todo, .guests: .activities
        case .places: .stays
        case .route: .car
        case .money, .numbers: .money
        case .options, .prices: .car
        case .overview: .neutral
        }
    }

    /// The option category this tab lists, when it's a list of things to vote on.
    var category: OptionCategory? {
        switch self {
        case .flights: .flights
        case .stays: .stays
        case .todo, .places: .activities
        default: nil
        }
    }

    /// The checklist item ("Decision") this tab settles.
    var decisionTitle: String? {
        switch self {
        case .flights: "Flights"
        case .stays: "Stays"
        case .todo: "Things to do"
        case .places: "Place"
        case .guests: "Who's in"
        case .options: "Buy out or return"
        default: nil
        }
    }
}

/// One tab Muse chose for this plan. The title is the plan's own word ("Theaters"), not a fixed label.
struct ShownTab: Identifiable, Hashable {
    enum Kind: String, Hashable { case overview, options, people, money, tasks, route, decision }

    var id: String
    var title: String
    var symbol: String
    var tint: Tint
    var kind: Kind
    /// The car screen still switches on these.
    var decision: PlanTab?

    static func make(id: String, title: String, kind: Kind) -> ShownTab {
        let (symbol, tint, decision) = chrome(id: id, kind: kind)
        return ShownTab(id: id, title: title, symbol: symbol, tint: tint, kind: kind, decision: decision)
    }

    private static func chrome(id: String, kind: Kind) -> (String, Tint, PlanTab?) {
        switch id {
        case "theaters": ("film", .activities, nil)
        case "food", "places": ("fork.knife", .stays, nil)
        case "flights": ("airplane", .flights, nil)
        case "stays": ("bed.double.fill", .stays, nil)
        case "todo": ("list.bullet", .activities, nil)
        case "guests": ("person.2.fill", .activities, nil)
        case "money": ("dollarsign.circle.fill", .money, nil)
        case "route": ("car.fill", .car, nil)
        case "gettingThere": ("tram.fill", .flights, nil)
        case "options": ("square.grid.2x2.fill", .car, .options)
        case "numbers": ("chart.bar.fill", .money, .numbers)
        case "prices": ("chart.line.downtrend.xyaxis", .car, .prices)
        default:
            switch kind {
            case .overview: ("sparkles.rectangle.stack", .neutral, nil)
            case .options: ("mappin.and.ellipse", .stays, nil)
            case .people: ("person.2.fill", .activities, nil)
            case .money: ("dollarsign.circle.fill", .money, nil)
            case .tasks: ("list.bullet", .activities, nil)
            case .route: ("map", .car, nil)
            case .decision: ("square.grid.2x2.fill", .car, .options)
            }
        }
    }
}

/// What Muse understood from the request: the kind of plan, and the details that shape it.
struct PlanSetup: Hashable {
    enum Style: String { case flightTrip, roadTrip, groundTrip, dinner, event, purchase }

    var style: Style
    var people: Int?
    var budget: String?
    /// Plain-language chips shown on the Overview ("Flying from Austin", "Vegan option").
    var chips: [String]
    /// The tabs for this plan. Nil only for a setup built before Muse named them.
    var tabs: [ShownTab]? = nil

    /// Keyword fallback. Muse returns the same shape from POST /plans/setup when it is on.
    static func infer(from request: String, kind: PlanKind, name: String = "", notes: String = "") -> PlanSetup {
        let text = "\(name) \(request) \(notes)".lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        let style: Style
        if kind == .decision || has("lease", "buyout", "buy out", "car deal") {
            style = .purchase
        } else if has("movie", "showtime", "theater", "theatre") {
            style = .event
        } else if has("dinner", "lunch", "brunch", "restaurant", "where should we eat") && !has("trip", "weekend", "flight") {
            style = .dinner
        } else if has("birthday", "bachelorette", "party", "wedding", "concert") && !has("flight", "fly") {
            style = .event
        } else if has("road trip", "drive", "driving", "my mom's driving") {
            style = .roadTrip
        } else if has("train", "bus", "amtrak") {
            style = .groundTrip
        } else if kind == .gathering || kind == .general, !has("flight", "fly", "trip") {
            style = .event
        } else {
            style = .flightTrip
        }

        var chips: [String] = []
        if style == .flightTrip, let from = match(#"from ([A-Z][a-zA-Z]+)"#, in: request) { chips.append("Flying from \(from)") }
        if style == .roadTrip { chips.append("Driving") }
        if style == .groundTrip { chips.append("Train or bus") }
        let people = match(#"(\d+)\s*(?:of us|people|adults|friends)"#, in: text).flatMap { Int($0) }
        if let people { chips.append("\(people) people") }
        let budget = match(#"(\$[\d,]+)\s*(?:each|pp|per person|a person)"#, in: text).map { "\($0) each" }
        if let budget { chips.append(budget) }
        if has("vegan") { chips.append("Vegan option") }
        if has("vegetarian") { chips.append("Vegetarian option") }
        if has("wheelchair", "accessible") { chips.append("Step-free only") }
        if has("queer", "lgbt") { chips.append("Queer-friendly") }
        if let near = match(#"near ([A-Z][a-zA-Z]+)"#, in: request) { chips.append("Near \(near)") }
        if has("secret", "surprise") { chips.append("Surprise: hidden from guest of honor") }
        return PlanSetup(style: style, people: people, budget: budget, chips: chips, tabs: ShownTab.forPlan(style: style, text: text, budget: budget != nil, people: people != nil))
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

extension Plan {
    var setup: PlanSetup {
        if let museSetup { return museSetup }
        let thread = messages.suffix(8).compactMap { message -> String? in
            if case .text(let text) = message.body { return text }
            return nil
        }.joined(separator: ". ")
        return .infer(from: request, kind: kind, name: name, notes: "\(nextStep). \(thread)")
    }

    /// The first list Muse filled, so Overview can open it.
    var nextTab: ShownTab? { tabs.first { $0.kind == .options } ?? tabs.first { $0.id != "overview" } }

    var kindName: String {
        switch kind {
        case .trip: "trip"
        case .decision: "decision"
        case .gathering: "gathering"
        case .general: "general"
        }
    }

    func applyMuseSetup(_ shape: HuddleAPI.PlanShape) {
        let fallback = setup
        var chosen: [ShownTab] = []
        for raw in shape.tabs {
            guard let kind = ShownTab.Kind(rawValue: raw.kind), !chosen.contains(where: { $0.id == raw.id }) else { continue }
            chosen.append(.make(id: raw.id, title: raw.title, kind: kind))
        }
        if chosen.first?.id != "overview" { chosen.insert(.make(id: "overview", title: "Overview", kind: .overview), at: 0) }
        museSetup = PlanSetup(
            style: PlanSetup.Style(rawValue: shape.style) ?? fallback.style,
            people: shape.people ?? fallback.people,
            budget: shape.budget ?? fallback.budget,
            chips: shape.chips.isEmpty ? fallback.chips : shape.chips,
            tabs: Array(chosen.prefix(5))
        )
    }

    /// Tabs Muse named for this plan. At most five.
    var tabs: [ShownTab] {
        let setup = setup
        let chosen = setup.tabs ?? ShownTab.forPlan(style: setup.style, text: "\(name) \(request)", budget: setup.budget != nil || decided("Budget") != nil, people: setup.people != nil)
        return Array(chosen.prefix(5))
    }

    /// Rows that belong on this tab. Untagged search results sit on the first list of their kind.
    func options(for tab: ShownTab) -> [BoardOption] {
        let tagged = options.filter { $0.listID == tab.id }
        if !tagged.isEmpty { return tagged }
        if tab.id == "flights" { return options.filter { $0.listID.isEmpty && $0.category == .flights } }
        if tab.id == "stays" { return options.filter { $0.listID.isEmpty && $0.category == .stays } }
        let lists = tabs.filter { $0.kind == .options && $0.id != "flights" && $0.id != "stays" }
        guard lists.first?.id == tab.id else { return [] }
        return options.filter { $0.listID.isEmpty && $0.category == .activities }
    }

    func ensureTab(_ id: String, title: String, kind: ShownTab.Kind) {
        var shaped = museSetup ?? setup
        var chosen = shaped.tabs ?? tabs
        guard !chosen.contains(where: { $0.id == id }) else { return }
        chosen.append(.make(id: id, title: title, kind: kind))
        shaped.tabs = Array(chosen.prefix(5))
        museSetup = shaped
    }
}

extension ShownTab {
    /// Local stand-in until Muse answers. A movie night gets Theaters, and Food only if the chat mentions eating.
    static func forPlan(style: PlanSetup.Style, text: String, budget: Bool, people: Bool) -> [ShownTab] {
        let low = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { low.contains($0) } }
        var rest: [ShownTab]
        if style == .purchase {
            rest = [.make(id: "options", title: "Options", kind: .decision), .make(id: "numbers", title: "Numbers", kind: .decision), .make(id: "prices", title: "Prices", kind: .decision)]
        } else if has("movie", "showtime", "theater", "theatre") {
            rest = [.make(id: "theaters", title: "Theaters", kind: .options)]
            if has("eat", "food", "dinner", "restaurant") { rest.append(.make(id: "food", title: "Food", kind: .options)) }
        } else if style == .dinner {
            rest = [.make(id: "places", title: "Places", kind: .options)]
            if people { rest.append(.make(id: "guests", title: "Who's in", kind: .people)) }
        } else if style == .roadTrip {
            rest = [.make(id: "route", title: "Route", kind: .route), .make(id: "stays", title: "Stays", kind: .options), .make(id: "todo", title: "Do", kind: .tasks)]
        } else if style == .groundTrip {
            rest = [.make(id: "gettingThere", title: "Getting there", kind: .route), .make(id: "stays", title: "Stays", kind: .options), .make(id: "todo", title: "Do", kind: .tasks)]
        } else if style == .event {
            rest = [.make(id: "places", title: "Places", kind: .options)]
            if people { rest.append(.make(id: "guests", title: "Who's in", kind: .people)) }
        } else {
            rest = [.make(id: "flights", title: "Flights", kind: .options), .make(id: "stays", title: "Stays", kind: .options), .make(id: "todo", title: "Do", kind: .tasks)]
        }
        if budget, style != .purchase, style != .dinner { rest.append(.make(id: "money", title: "Money", kind: .money)) }
        return [.make(id: "overview", title: "Overview", kind: .overview)] + rest
    }
}

// MARK: - Money

extension Plan {
    struct CostLine: Identifiable, Hashable {
        var id: String { label }
        var label: String
        var detail: String
        var perPerson: Double
    }

    private static func dollars(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    private static func count(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    var travelers: Int { setup.people ?? members.count }

    /// Per-person estimate from what's leading in each category, so the budget is always current.
    func costLines(watch: (String?) -> PriceWatch?) -> [CostLine] {
        var lines: [CostLine] = []
        let leading = { (cat: OptionCategory) in
            self.options.filter { $0.category == cat }.max { $0.upVotes < $1.upVotes }
        }
        if let f = leading(.flights), let price = watch(f.watchID)?.current ?? Self.dollars(f.price) {
            lines.append(CostLine(label: "Flights", detail: f.title, perPerson: price))
        }
        let stays = options.filter { $0.category == .stays && $0.isTopPick }
        for s in (stays.isEmpty ? [leading(.stays)].compactMap { $0 } : stays) {
            guard let rate = watch(s.watchID)?.current ?? Self.dollars(s.price) else { continue }
            let nights = Self.count(#"(\d+)\s*nights?"#, in: s.detail) ?? 1
            let rooms = Self.count(#"(\d+)\s*(?:twin\s*)?rooms?"#, in: s.detail) ?? 1
            let group = s.unit.contains("night") ? rate * Double(nights) * Double(s.unit.contains("room") ? rooms : 1) : rate
            lines.append(CostLine(label: s.title, detail: "\(nights) nights", perPerson: group / Double(max(1, travelers))))
        }
        for a in options.filter({ $0.category == .activities && $0.upVotes > 0 }) {
            if let price = Self.dollars(a.price) { lines.append(CostLine(label: a.title, detail: "Ticket", perPerson: price)) }
        }
        return lines
    }

    var budgetPerPerson: Double? {
        (decided("Budget") ?? setup.budget).flatMap { Self.dollars($0.components(separatedBy: " ").first ?? $0) }
    }
}
