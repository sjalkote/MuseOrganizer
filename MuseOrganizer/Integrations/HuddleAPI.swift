import Foundation

/// The Huddle backend: live SerpApi searches, Muse Spark writing and advice, and the price watch.
/// Configured by HUDDLE_BACKEND_URL (launch argument `-HUDDLE_BACKEND_URL http://127.0.0.1:8000` or build setting).
struct HuddleAPI {
    var baseURL: URL
    var session: URLSession = .shared

    /// nil when no backend is set up; the app then shows labeled demo data.
    static var configured: HuddleAPI? {
        let raw = UserDefaults.standard.string(forKey: "HUDDLE_BACKEND_URL")
            ?? Bundle.main.object(forInfoDictionaryKey: "HUDDLE_BACKEND_URL") as? String
        guard let raw, !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { return nil }
        return HuddleAPI(baseURL: url)
    }

    struct Board: Decodable {
        struct Option: Decodable {
            var id, category, title, detail, unit, tradeoff, source: String
            var price: Double?
            var priceLabel: String?
            var link: String?
            var watchId: String?
        }
        var options: [Option]
        var watches: [PriceWatch]
        var live: LiveStatus
    }

    struct Watches: Decodable { var watches: [PriceWatch]; var alerts: [PriceAdvice] }
    struct Checked: Decodable { var alerts: [PriceAdvice]; var watches: [PriceWatch] }
    struct Alerts: Decodable { var alerts: [PriceAdvice]; var now: Double }
    struct Answer: Decodable { var text: String; var live: Bool; var options: [Board.Option] }
    struct Status: Decodable { var muse: Bool; var serpapi: Bool; var watchInterval: Double }

    func status() async throws -> Status { try await get("status") }
    func board(planID: String, trip: TripQuery) async throws -> Board { try await post("plans/\(planID)/board", trip) }
    func watches(planID: String) async throws -> Watches { try await get("plans/\(planID)/watches") }
    func check(planID: String) async throws -> Checked { try await post("plans/\(planID)/watches/check", Empty()) }
    func alerts(since: Double) async throws -> Alerts { try await get("alerts", query: ["since": String(since)]) }
    func ask(planID: String, question: String, name: String, kind: String) async throws -> Answer {
        try await post("plans/\(planID)/ask", ["question": question, "name": name, "kind": kind])
    }
    func addWatch(planID: String, _ request: WatchRequest) async throws -> PriceWatch {
        try await post("plans/\(planID)/watches", request)
    }

    // MARK: Plumbing

    private struct Empty: Encodable {}
    private struct ServerError: Decodable { var detail: String }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) }) }
        return try await send(URLRequest(url: url))
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data))?.detail
            throw WorkspaceError.server(detail ?? "The NxT backend returned \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
