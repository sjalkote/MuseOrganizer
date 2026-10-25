import SwiftUI

/// One price Muse keeps an eye on: a flight route, a hotel, used-car listings. Mirrors backend/huddle/watch.py.
struct PriceWatch: Identifiable, Hashable, Codable {
    let id: String
    var planId: String
    var category: String
    var label: String
    var detail: String
    var unit: String
    var neededBy: String?
    var baseline: Double?
    var current: Double?
    var low: Double?
    var high: Double?
    /// `[unix seconds, price]`, oldest first.
    var history: [[Double]]
    var checkedAt: Double?
    var advice: PriceAdvice?

    var prices: [Double] { history.compactMap { $0.count == 2 ? $0[1] : nil } }

    /// Change since Muse started watching (negative is cheaper).
    var change: Double? {
        guard let current, let baseline else { return nil }
        return current - baseline
    }

    var isAtLow: Bool {
        guard let current, let low else { return false }
        return current <= low + 0.5
    }

    var lastChecked: Date? { checkedAt.map { Date(timeIntervalSince1970: $0) } }
}

/// Muse Spark's call on a price move: book now, wait, or keep watching.
struct PriceAdvice: Identifiable, Hashable, Codable {
    let id: String
    var watchId: String
    var planId: String
    var at: Double
    var old: Double
    var new: Double
    var verdict: Verdict
    var headline: String
    var reason: String

    enum Verdict: String, Codable, Hashable {
        case book, wait, watch

        var title: String {
            switch self {
            case .book: "Book now"
            case .wait: "Wait"
            case .watch: "Keep watching"
            }
        }

        var symbol: String {
            switch self {
            case .book: "checkmark.seal.fill"
            case .wait: "hourglass"
            case .watch: "eye.fill"
            }
        }

        var color: Color {
            switch self {
            case .book: Palette.positive
            case .wait: Palette.caution
            case .watch: Palette.accent
            }
        }
    }

    var date: Date { Date(timeIntervalSince1970: at) }
    var drop: Double { old - new }
}

/// Which services the backend is actually calling. Anything not live is shown as demo data.
struct LiveStatus: Codable, Hashable {
    var muse: Bool
    var serpapi: Bool
}

enum Money {
    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// "▼ $64" / "▲ $12"
    static func change(_ value: Double) -> String {
        "\(value < 0 ? "▼" : "▲") \(format(abs(value)))"
    }
}

// MARK: - Demo watches
// Shown only when no backend is configured, always under a "Demo data" label.

extension Mock {
    private static func series(_ values: [Double], endingAt end: Date = .now, every days: Double = 3) -> [[Double]] {
        let last = end.timeIntervalSince1970
        return values.enumerated().map { i, v in [last - Double(values.count - 1 - i) * days * 86_400, v] }
    }

    static func demoWatches(for planID: String) -> [PriceWatch] {
        switch planID {
        case "japan":
            let ana = series([1262, 1240, 1255, 1231, 1218, 1226, 1212, 1198, 1205, 1212, 1148])
            let jal = series([1295, 1301, 1310, 1288, 1297, 1305, 1312, 1306, 1318, 1309, 1312])
            let gracery = series([158, 160, 156, 161, 159, 163, 156, 162, 168], every: 4)
            let machiya = series([214, 214, 220, 214, 214, 209, 214, 214], every: 4)
            return [
                PriceWatch(id: "demo-ana", planId: planID, category: "flights", label: "ANA · AUS → HND",
                           detail: "Mar 26 – Apr 4 · 4 travelers", unit: "per person", neededBy: "2027-03-26",
                           baseline: 1212, current: 1148, low: 1148, high: 1262, history: ana,
                           checkedAt: ana.last?[0],
                           advice: PriceAdvice(id: "demo-a1", watchId: "demo-ana", planId: planID, at: ana.last![0],
                                               old: 1212, new: 1148, verdict: .book,
                                               headline: "ANA dropped $64 to $1,148",
                                               reason: "That's the lowest in 30 days of Google Flights history. Typical is $1,150–$1,380.")),
                PriceWatch(id: "demo-jal", planId: planID, category: "flights", label: "JAL · AUS → NRT",
                           detail: "Mar 26 – Apr 4 · 4 travelers", unit: "per person", neededBy: "2027-03-26",
                           baseline: 1295, current: 1312, low: 1288, high: 1318, history: jal, checkedAt: jal.last?[0]),
                PriceWatch(id: "demo-gracery", planId: planID, category: "stays", label: "Hotel Gracery Shinjuku",
                           detail: "Mar 26 – 30 · Shinjuku", unit: "per night", neededBy: "2027-03-26",
                           baseline: 158, current: 168, low: 156, high: 168, history: gracery, checkedAt: gracery.last?[0],
                           advice: PriceAdvice(id: "demo-a2", watchId: "demo-gracery", planId: planID, at: gracery.last![0] - 3_600,
                                               old: 156, new: 168, verdict: .wait,
                                               headline: "Hotel Gracery rose $12 to $168",
                                               reason: "Still 5 months out. It was $156 last week, so it may come back down.")),
                PriceWatch(id: "demo-machiya", planId: planID, category: "stays", label: "Kyoto Machiya House",
                           detail: "Mar 30 – Apr 2 · Kyoto", unit: "per night", neededBy: "2027-03-30",
                           baseline: 214, current: 214, low: 209, high: 220, history: machiya, checkedAt: machiya.last?[0]),
            ]
        case "car":
            let cars = series([28_400, 28_250, 28_310, 28_100, 28_090, 27_950, 28_020, 27_495], every: 5)
            return [
                PriceWatch(id: "demo-rav4", planId: planID, category: "car", label: "Used RAV4 XLE near Austin",
                           detail: "2023 · about 37k miles · cheapest listing", unit: "per car", neededBy: nil,
                           baseline: 28_400, current: 27_495, low: 27_495, high: 28_400, history: cars, checkedAt: cars.last?[0],
                           advice: PriceAdvice(id: "demo-a3", watchId: "demo-rav4", planId: planID, at: cars.last![0],
                                               old: 28_020, new: 27_495, verdict: .watch,
                                               headline: "Used RAV4s dropped $525 to $27,495",
                                               reason: "Your $24,180 buyout is still $3,315 under the cheapest listing, so buying out stays the better deal.")),
            ]
        default:
            return []
        }
    }
}

// MARK: - What the board search needs

/// The trip facts the backend turns into live SerpApi searches (backend/huddle/board.py).
struct TripQuery: Encodable, Hashable {
    struct Flight: Encodable, Hashable { var from, to, depart: String; var `return`: String }
    struct Stay: Encodable, Hashable { var area, checkIn, checkOut: String; var rooms: Int }

    var travelers: Int
    var budgetPerPerson: Double?
    var flights: [Flight]
    var stays: [Stay]
    var activities: [String]
}

/// A watch the app asks for directly (the car plan's listings).
struct WatchRequest: Encodable {
    var category, label, engine: String
    var params: [String: String]
    var match = ""
    var detail = ""
    var unit = ""
    var neededBy: String?
}
