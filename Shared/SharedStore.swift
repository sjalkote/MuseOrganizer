import Foundation

/// Data shared between the Huddle app, its iMessage app, and its share extension.
/// Everything lives in the App Group so each piece sees the same plans.
enum AppGroup {
    static let id = "group.com.sjalkote.MuseOrganizer"
}

/// Something a person shared into Huddle from another app (an Instagram reel, a WhatsApp message, a link).
struct SharedItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String?
    var text: String?
    var source: String          // "Instagram", "WhatsApp", "Safari", ...
    var sharedBy: String        // display name
    var planID: String?
    var category: String?       // "Flights", "Stays", "Things to do"
    var note: String = ""
    var date = Date()
    var added = false
}

/// A lightweight copy of a plan, readable by the extensions.
struct PlanSnapshot: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var chatName: String
    var source: String
    var decided: Int
    var total: Int
    var nextStep: String
    var memberNames: [String]
    var options: [Option]

    struct Option: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String
        var price: String
        var category: String
        var votes: Int
    }
}

enum SharedStore {
    private static let itemsKey = "sharedItems"
    private static let plansKey = "planSnapshots"

    static var defaults: UserDefaults { UserDefaults(suiteName: AppGroup.id) ?? .standard }

    // MARK: Shared items

    static func items() -> [SharedItem] {
        guard let data = defaults.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([SharedItem].self, from: data) else { return [] }
        return items
    }

    static func add(_ item: SharedItem) {
        var all = items()
        all.insert(item, at: 0)
        save(all)
    }

    static func update(_ item: SharedItem) {
        var all = items()
        if let i = all.firstIndex(where: { $0.id == item.id }) { all[i] = item }
        save(all)
    }

    private static func save(_ items: [SharedItem]) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: itemsKey) }
    }

    // MARK: Plan snapshots

    static func plans() -> [PlanSnapshot] {
        guard let data = defaults.data(forKey: plansKey),
              let plans = try? JSONDecoder().decode([PlanSnapshot].self, from: data) else { return PlanSnapshot.samples }
        return plans
    }

    static func save(plans: [PlanSnapshot]) {
        if let data = try? JSONEncoder().encode(plans) { defaults.set(data, forKey: plansKey) }
    }

    // MARK: Helpers

    /// Guess which app a shared link came from.
    static func source(for url: URL?) -> String {
        guard let host = url?.host()?.lowercased() else { return "Message" }
        if host.contains("instagram") { return "Instagram" }
        if host.contains("whatsapp") || host.contains("wa.me") { return "WhatsApp" }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("google") { return "Google" }
        return "Safari"
    }
}

/// Links that open a plan from iMessage, a share, or a WhatsApp post: huddle://plan/japan
enum DeepLink {
    static func plan(_ id: String) -> URL { URL(string: "huddle://plan/\(id)")! }
    static func web(_ id: String) -> URL { URL(string: "https://huddle.app/p/\(id)")! }

    static func planID(from url: URL) -> String? {
        if url.scheme == "huddle", url.host() == "plan" { return url.pathComponents.dropFirst().first }
        if url.host() == "huddle.app", url.pathComponents.count > 2 { return url.pathComponents[2] }
        return nil
    }
}

extension PlanSnapshot {
    /// Used when the app hasn't written its plans yet (first launch of an extension).
    static let samples: [PlanSnapshot] = [
        PlanSnapshot(id: "japan", name: "Japan Trip 2027", chatName: "Japan crew", source: "WhatsApp",
                     decided: 3, total: 5, nextStep: "Book flights by Friday",
                     memberNames: ["Devin", "Sam", "Maya", "Jordan"], options: [
                        .init(id: "ana", title: "ANA via LAX", detail: "1 stop · 17h 40m", price: "$1,148", category: "Flights", votes: 3),
                        .init(id: "jal", title: "JAL via DFW", detail: "1 stop · 16h 05m", price: "$1,312", category: "Flights", votes: 1),
                        .init(id: "united", title: "United via SFO", detail: "Leaves Mar 27", price: "$1,089", category: "Flights", votes: 0),
                     ]),
        PlanSnapshot(id: "car", name: "Our next car", chatName: "Family", source: "iMessage",
                     decided: 1, total: 3, nextStep: "Book a dealer visit before July",
                     memberNames: ["Devin", "Mom", "Dad", "Priya"], options: [
                        .init(id: "buyout", title: "Buy out", detail: "60-month loan", price: "$478/mo", category: "Options", votes: 3),
                        .init(id: "lease", title: "Return and lease new", detail: "Plus ~$1,140 fees", price: "$429/mo", category: "Options", votes: 1),
                     ]),
    ]
}
