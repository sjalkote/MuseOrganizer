import Foundation

// MARK: - Models (mirror backend/huddle/api.py JSON; snake_case is converted automatically)

struct SessionInfo: Codable {
    let id: String
    let template: String
    let title: String
    let context: [String: String]
    let members: [String: String]
}

struct Joined: Codable {
    let memberId: String
    let id: String
    let title: String
    let members: [String: String]
}

struct Message: Codable {
    let author: String
    let text: String
    var cards: [Card]? = nil
}

struct Card: Codable {
    let type: String
    let option: CarOption
}

struct CarOption: Codable, Identifiable {
    let name: String
    let msrp: Int
    let mpg: Int
    let seats: Int
    let cargo: Int
    let awd: Bool
    let estMonthly: Int
    let score: Int
    let fitsAll: Bool
    let finance: FinancePlans
    var listings: [Listing]? = nil
    var id: String { name }
}

struct FinancePlans: Codable {
    let months: Int
    let best: String
    let cash: Plan
    let finance: Plan
    let lease: Plan

    subscript(key: String) -> Plan {
        switch key {
        case "cash": cash
        case "lease": lease
        default: finance
        }
    }
}

struct Plan: Codable {
    let upfront: Int
    let monthly: Int
    let totalPaid: Int
    let interest: Int
    let equity: Int
    let netCost: Int
}

struct Listing: Codable {
    let title: String?
    let link: String?
}

/// A group this device has joined, remembered across launches.
struct GroupRef: Codable, Hashable, Identifiable {
    let sessionId: String
    let memberId: String
    let title: String
    let myName: String
    var id: String { sessionId }
}

// MARK: - Client

enum API {
    // ponytail: hardcoded simulator address; read from settings when testing on a real device.
    static let base = URL(string: "http://127.0.0.1:8000")!

    struct ServerError: LocalizedError {
        let errorDescription: String?
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func send<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: base.appending(path: path))
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw ServerError(errorDescription: detail ?? "Server error \(http.statusCode)")
        }
        return try decoder.decode(T.self, from: data)
    }

    static func create(template: String, location: String) async throws -> SessionInfo {
        try await send("sessions", body: ["template": template, "context": ["location": location]])
    }
    static func join(_ sid: String, name: String) async throws -> Joined {
        try await send("sessions/\(sid)/join", body: ["name": name])
    }
    static func info(_ sid: String) async throws -> SessionInfo {
        try await send("sessions/\(sid)")
    }
    static func group(_ sid: String) async throws -> [Message] {
        try await send("sessions/\(sid)/group")
    }
    static func say(_ sid: String, _ mid: String, _ text: String) async throws -> [Message] {
        try await send("sessions/\(sid)/group/\(mid)", body: ["text": text])
    }
    static func run(_ sid: String) async throws -> [Message] {
        try await send("sessions/\(sid)/run", body: [:])
    }
    static func thread(_ sid: String, _ mid: String) async throws -> [Message] {
        try await send("sessions/\(sid)/private/\(mid)")
    }
    static func tell(_ sid: String, _ mid: String, _ text: String) async throws -> [Message] {
        try await send("sessions/\(sid)/private/\(mid)", body: ["text": text])
    }
    static func explain(_ sid: String, _ mid: String, option: String) async throws -> [Message] {
        try await send("sessions/\(sid)/private/\(mid)/explain/\(option)", body: [:])
    }
}
