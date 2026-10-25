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

/// What Muse understood from the request: the kind of plan, and the details that shape it.
struct PlanSetup: Hashable {
    enum Style: String { case flightTrip, roadTrip, groundTrip, dinner, event, purchase }

    var style: Style
    var people: Int?
    var budget: String?
    /// Plain-language chips shown on the Overview ("Flying from Austin", "Vegan option").
    var chips: [String]

    /// Keyword rules for now; Muse returns the same shape from the backend when it's live.
    static func infer(from request: String, kind: PlanKind) -> PlanSetup {
        let text = request.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        let style: Style
        if kind == .decision || has("lease", "buyout", "buy out", "car deal") {
            style = .purchase
        } else if has("dinner", "lunch", "brunch", "restaurant", "where should we eat") && !has("trip", "weekend", "flight") {
            style = .dinner
        } else if has("birthday", "bachelorette", "party", "wedding", "concert") && !has("flight", "fly") {
            style = .event
        } else if has("road trip", "drive", "driving", "my mom's driving") {
            style = .roadTrip
        } else if has("train", "bus", "amtrak") {
            style = .groundTrip
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
        return PlanSetup(style: style, people: people, budget: budget, chips: chips)
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

extension Plan {
    var setup: PlanSetup { .infer(from: request, kind: kind) }

    /// At most five tabs, chosen by the kind of plan. Money only shows once there's a budget,
    /// and a list tab only shows once it has options (or Muse is still searching for them).
    var tabs: [PlanTab] {
        let setup = setup
        let all: [PlanTab] = switch setup.style {
        case .flightTrip: [.overview, .flights, .stays, .todo, .money]
        case .roadTrip: [.overview, .route, .stays, .todo, .money]
        case .groundTrip: [.overview, .gettingThere, .stays, .todo, .money]
        case .dinner: [.overview, .places, .guests]
        case .event: [.overview, .places, .guests, .todo, .money]
        case .purchase: [.overview, .options, .numbers, .prices]
        }
        return all.filter { tab in
            if tab == .money { return setup.budget != nil || decided("Budget") != nil }
            return true
        }
    }

    func decision(for tab: PlanTab) -> Decision? {
        guard let title = tab.decisionTitle else { return nil }
        return decisions.first { $0.title == title }
    }

    /// The tab where the group has something to do next: the first one still being voted on, then the first open one.
    var nextTab: PlanTab? {
        let candidates = tabs.filter { $0 != .overview }
        if let t = candidates.first(where: { if case .voting = decision(for: $0)?.state { true } else { false } }) { return t }
        return candidates.first { if case .open = decision(for: $0)?.state { true } else { false } }
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
