import SwiftUI

struct Member: Identifiable, Hashable {
    let id: String
    var name: String
    /// Asset catalog image name. Falls back to a monogram when missing.
    var photo: String?
    var isMe = false

    var firstName: String { isMe ? "You" : (name.components(separatedBy: " ").first ?? name) }
    var initial: String { String(name.prefix(1)) }

    /// Stable personal color for monograms and name labels.
    var tint: Tint {
        let all: [Tint] = [.flights, .stays, .activities, .money, .dates, .car]
        let index = abs(id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % all.count
        return all[index]
    }
}

/// The messaging app a plan is linked to. Shown as words + SF Symbol, never third-party logos.
enum ChatSource: String, CaseIterable, Identifiable {
    case whatsapp = "WhatsApp"
    case imessage = "iMessage"
    case instagram = "Instagram"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .whatsapp: "phone.bubble"
        case .imessage: "message"
        case .instagram: "camera"
        }
    }

    /// Recognizable app color, without using the app's logo.
    var tint: Tint {
        switch self {
        case .whatsapp: Tint(strong: Color(light: 0x128C4B, dark: 0x4CD388), soft: Color(light: 0xE1F5E9, dark: 0x12301F))
        case .imessage: Tint(strong: Color(light: 0x1F6FD1, dark: 0x6AAEFF), soft: Color(light: 0xE5EFFC, dark: 0x13233A))
        case .instagram: Tint(strong: Color(light: 0xC0306A, dark: 0xFF7EB0), soft: Color(light: 0xFCE7EF, dark: 0x351A26))
        }
    }
}

enum PlanKind { case trip, decision }

// MARK: Decisions (the plan's checklist)

struct Decision: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var symbol: String
    var tint: Tint
    var state: State

    enum State: Hashable {
        case decided(String)
        case voting(String)
        case open(String)
    }

    var isDecided: Bool { if case .decided = state { true } else { false } }
}

// MARK: Thread

/// What the Planner posts into the group chat: a compact card everyone sees in WhatsApp / iMessage.
struct PlannerPost: Hashable {
    var text: String
    var card: Card? = nil
    var trace: [String] = []      // e.g. "Google Flights · 2.1s"

    struct Card: Hashable {
        var title: String
        var rows: [Row]
        var action: String

        struct Row: Hashable, Identifiable {
            var id: String { label }
            var label: String
            var detail: String
            var value: String
        }
    }
}

enum MessageBody: Hashable {
    case text(String)
    case planner(PlannerPost)
    case event(String)
}

struct Message: Identifiable, Hashable {
    let id = UUID()
    var senderID: String     // "planner" for the AI
    var body: MessageBody
    var time: String
}

// MARK: Trip options

enum OptionCategory: String, CaseIterable, Identifiable {
    case flights = "Flights"
    case stays = "Stays"
    case activities = "Things to do"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .flights: "airplane"
        case .stays: "bed.double"
        case .activities: "ticket"
        }
    }

    var tint: Tint {
        switch self {
        case .flights: .flights
        case .stays: .stays
        case .activities: .activities
        }
    }
}

struct BoardOption: Identifiable, Hashable {
    let id = UUID()
    var category: OptionCategory
    var title: String
    var detail: String
    var price: String
    var unit: String
    var tradeoff: String
    var source: String
    var fetched: String
    var upVotes: Int
    var downVotes: Int
    var myVote: Vote = .none
    var isTopPick = false
    var sharedBy: String? = nil      // member id, when it came from a shared link
    var sharedFrom: ChatSource? = nil

    enum Vote { case up, down, none }
}

struct ItineraryDay: Identifiable, Hashable {
    let id = UUID()
    var day: Int
    var date: String
    var city: String
    var slots: [Slot]

    struct Slot: Identifiable, Hashable {
        let id = UUID()
        var time: String
        var title: String
        var detail: String
    }
}

// MARK: Car decision

struct LeaseSnapshot {
    var vehicle: String
    var monthsRemaining: Int
    var monthlyPayment: Int
    var milesUsed: Int
    var milesAllowed: Int
    var residualValue: Int
    var marketValue: Int
}

struct LeaseOption: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var monthly: String
    var total: String
    var totalLabel: String
    var tradeoff: String
    var votes: [String]   // member ids
    var isRecommended = false
}

struct Assumption: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var value: String
    var source: String
}

// MARK: Planner activity

struct AgentStep: Identifiable, Hashable {
    let id = UUID()
    var tool: String
    var detail: String
    var engine: String      // "SerpApi · google_flights", "Muse Spark", ...
    var duration: Double
    var credits: Int
}

struct SourceRef: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var detail: String
}
