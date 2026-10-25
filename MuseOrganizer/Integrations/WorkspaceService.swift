import SwiftUI

/// Progress events while a plan folder is being built.
enum BuildEvent {
    case planned(WorkspaceBlueprint)
    case researching(ResearchCall.ID)
    case researched(ResearchCall.ID, result: String, duration: Double)
    case writing(WorkspaceFile.ID)
    case wrote(WorkspaceFile.ID, summary: String)
    case finished(PlanWorkspace)
}

/// Builds a Google Drive folder for a plan. `WorkspaceServices.makeDefault()` picks the real
/// backend when one is configured (see docs/GOOGLE_WORKSPACE_SETUP.md).
protocol WorkspaceService {
    func build(_ plan: Plan) -> AsyncThrowingStream<BuildEvent, Error>
}

/// Demo implementation: replays the blueprint with realistic timing, no network.
struct SimulatedWorkspaceService: WorkspaceService {
    var speed: Double = 1

    func build(_ plan: Plan) -> AsyncThrowingStream<BuildEvent, Error> {
        let blueprint = Mock.blueprint(for: plan)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.planned(blueprint))
                for call in blueprint.calls {
                    continuation.yield(.researching(call.id))
                    try await Task.sleep(for: .milliseconds(Int(min(call.duration, 1.2) * 550 / speed)))
                    continuation.yield(.researched(call.id, result: call.result, duration: call.duration))
                }
                for file in blueprint.files {
                    continuation.yield(.writing(file.id))
                    try await Task.sleep(for: .milliseconds(Int(700 / speed)))
                    continuation.yield(.wrote(file.id, summary: file.summary))
                }
                let slug = blueprint.folderName.lowercased().replacingOccurrences(of: " ", with: "-")
                continuation.yield(.finished(PlanWorkspace(
                    folderName: blueprint.folderName,
                    url: URL(string: "https://drive.google.com/drive/folders/huddle-\(slug)")!,
                    files: blueprint.files, calls: blueprint.calls, builtAt: .now, sharedTo: nil
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Talks to the Huddle backend, which holds the SerpApi key, the Muse Spark key and the Google token
/// (backend/huddle/workspace.py):
///
///   POST   /plans/{id}/workspace          -> starts a build from the blueprint, returns a build id
///   GET    /builds/{buildId}/events (SSE)  -> researching / researched / writing / wrote / finished
///   DELETE /builds/{buildId}               -> cancels and deletes anything already written
///
/// The backend echoes the blueprint's call and file ids, so progress lines up with the list on screen.
struct GoogleWorkspaceService: WorkspaceService {
    var baseURL: URL
    var session: URLSession = .shared

    func build(_ plan: Plan) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buildID: String?
                var chosen: WorkspaceBlueprint?
                do {
                    var request = URLRequest(url: baseURL.appending(path: "plans/\(plan.id)/workspace"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(PlanSnapshotBody(plan))
                    let (data, response) = try await session.data(for: request)
                    try Self.check(response, data)
                    let id = try JSONDecoder().decode(Started.self, from: data).buildId
                    buildID = id

                    let (bytes, eventsResponse) = try await session.bytes(from: baseURL.appending(path: "builds/\(id)/events"))
                    try Self.check(eventsResponse, nil)
                    var name = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = Data(line.dropFirst(5).utf8)
                            if let event = try Self.event(name, payload, chosen: &chosen) {
                                continuation.yield(event)
                                if case .finished = event { break }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled, let buildID { cancel(buildID) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func cancel(_ buildID: String) {
        var request = URLRequest(url: baseURL.appending(path: "builds/\(buildID)"))
        request.httpMethod = "DELETE"
        let session = session
        Task.detached { _ = try? await session.data(for: request) }
    }

    private static func check(_ response: URLResponse, _ body: Data?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let detail = body.flatMap { try? JSONDecoder().decode(ServerError.self, from: $0) }?.detail
        throw WorkspaceError.server(detail ?? "The NxT backend returned \(http.statusCode).")
    }

    private static func event(_ name: String, _ payload: Data, chosen: inout WorkspaceBlueprint?) throws -> BuildEvent? {
        let decoder = JSONDecoder()
        switch name {
        case "planned":
            let planned = try decoder.decode(Planned.self, from: payload)
            let blueprint = planned.blueprint()
            chosen = blueprint
            return .planned(blueprint)
        case "researching", "researched", "writing", "wrote":
            let step = try decoder.decode(Step.self, from: payload)
            guard let id = UUID(uuidString: step.id) else { return nil }
            switch name {
            case "researching": return .researching(id)
            case "researched": return .researched(id, result: step.result ?? "", duration: step.duration ?? 0)
            case "writing": return .writing(id)
            default: return .wrote(id, summary: step.summary ?? "")
            }
        case "finished":
            let finished = try decoder.decode(Finished.self, from: payload)
            let blueprint = chosen ?? WorkspaceBlueprint(folderName: finished.folderName, calls: [], files: [])
            return .finished(finished.workspace(from: blueprint))
        case "failed":
            let failed = try decoder.decode(Failed.self, from: payload)
            throw WorkspaceError.server(failed.message)
        case "cancelled":
            throw CancellationError()
        default:
            return nil
        }
    }
}

/// Uses the backend when HUDDLE_BACKEND_URL is set, either as a launch argument
/// (`-HUDDLE_BACKEND_URL http://localhost:8000`) or as a build setting; otherwise the simulated build.
enum WorkspaceServices {
    static func makeDefault() -> WorkspaceService {
        let raw = UserDefaults.standard.string(forKey: "HUDDLE_BACKEND_URL")
            ?? Bundle.main.object(forInfoDictionaryKey: "HUDDLE_BACKEND_URL") as? String
        guard let raw, !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else {
            return SimulatedWorkspaceService()
        }
        return GoogleWorkspaceService(baseURL: url)
    }
}

enum WorkspaceError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self {
        case .server(let message): message
        }
    }
}

// MARK: Backend JSON

/// What Muse sees. No file list: the backend chooses the searches and the Sheets and Docs.
private struct PlanSnapshotBody: Encodable {
    struct DecisionBody: Encodable { var title, choice: String }
    struct OptionBody: Encodable { var title, detail, price, category: String }
    struct SlotBody: Encodable { var time, title, detail: String }
    struct DayBody: Encodable { var date, city: String; var slots: [SlotBody] }

    var name, kind, notes: String
    var members: [String]
    var decisions: [DecisionBody]
    var options: [OptionBody]
    var itinerary: [DayBody]
    var messages: [String]
    var context: [String: String]

    init(_ plan: Plan) {
        name = plan.name
        switch plan.kind {
        case .trip: kind = "trip"
        case .decision: kind = "car"
        case .gathering, .general: kind = "plan"
        }
        notes = plan.nextStep
        members = plan.members.map(\.name)
        decisions = plan.decisions.map { d in
            let choice: String
            switch d.state {
            case .decided(let s), .voting(let s), .open(let s): choice = s
            }
            return DecisionBody(title: d.title, choice: choice)
        }
        options = plan.options.map {
            OptionBody(title: $0.title, detail: $0.detail, price: $0.price, category: $0.category.rawValue)
        } + plan.leaseOptions.map {
            OptionBody(title: $0.title, detail: $0.totalLabel, price: $0.monthly, category: "Options")
        }
        itinerary = plan.itinerary.map { day in
            DayBody(date: day.date, city: day.city, slots: day.slots.map {
                SlotBody(time: $0.time, title: $0.title, detail: $0.detail)
            })
        }
        messages = plan.messages.suffix(12).map { m in
            switch m.body {
            case .text(let t): t
            case .planner(let p): p.text
            case .event(let e): e
            }
        }
        context = plan.kind == .decision
            ? ["buyoutPrice": "24180", "simulated": "1", "vehicle": "2023 Toyota RAV4 XLE", "location": "Austin, TX"]
            : [:]
    }
}

private struct Planned: Decodable {
    struct Call: Decodable { var id, engine, query: String }
    struct File: Decodable { var id, name, kind: String }
    var folderName: String
    var calls: [Call]
    var files: [File]

    func blueprint() -> WorkspaceBlueprint {
        WorkspaceBlueprint(
            folderName: folderName,
            calls: calls.compactMap { c -> ResearchCall? in
                guard let id = UUID(uuidString: c.id) else { return nil }
                return ResearchCall(id: id, engine: c.engine, query: c.query, result: "", duration: 0)
            },
            files: files.compactMap { f -> WorkspaceFile? in
                guard let id = UUID(uuidString: f.id) else { return nil }
                let kind = WorkspaceFileKind(rawValue: f.kind) ?? .doc
                let content: FileContent = kind == .sheet
                    ? .sheet(columns: [], rows: [], footer: nil)
                    : .doc([])
                return WorkspaceFile(id: id, name: f.name, kind: kind, summary: "", sources: [], content: content)
            }
        )
    }
}

/// `{columns, rows, footer}` for a sheet, `{blocks: [{type, text}]}` for a doc.
private struct ContentJSON: Codable {
    struct Block: Codable { var type, text: String }
    var columns: [String]?
    var rows: [[String]]?
    var footer: String?
    var blocks: [Block]?

    var fileContent: FileContent? {
        if let columns, let rows { return .sheet(columns: columns, rows: rows, footer: footer) }
        guard let blocks else { return nil }
        return .doc(blocks.map {
            switch $0.type {
            case "title": .title($0.text)
            case "heading": .heading($0.text)
            case "bullet": .bullet($0.text)
            default: .paragraph($0.text)
            }
        })
    }
}

private struct Started: Decodable { var buildId: String }
private struct Step: Decodable {
    var id: String
    var result: String?
    var duration: Double?
    var summary: String?
}
private struct Failed: Decodable { var message: String }
private struct ServerError: Decodable { var detail: String }

private struct Finished: Decodable {
    struct File: Decodable { var id, summary: String; var sources: [String]; var content: ContentJSON? }
    struct Call: Decodable { var id, result: String; var duration: Double }

    var folderName: String
    var url: URL
    var files: [File]
    var calls: [Call]

    /// The blueprint's files and calls (same ids) with what the backend actually found and wrote.
    func workspace(from blueprint: WorkspaceBlueprint) -> PlanWorkspace {
        let files = Dictionary(self.files.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let calls = Dictionary(self.calls.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return PlanWorkspace(
            folderName: folderName, url: url,
            files: blueprint.files.map { file in
                guard let out = files[file.id.uuidString] else { return file }
                var file = file
                file.summary = out.summary.isEmpty ? file.summary : out.summary
                file.sources = out.sources.isEmpty ? file.sources : out.sources
                file.content = out.content?.fileContent ?? file.content
                return file
            },
            calls: blueprint.calls.map { call in
                guard let out = calls[call.id.uuidString] else { return call }
                var call = call
                call.result = out.result
                call.duration = out.duration
                return call
            },
            builtAt: .now, sharedTo: nil
        )
    }
}

// MARK: - Live build state for the UI

@Observable
final class BuildSession {
    enum Status: Hashable { case queued, running, done }

    var blueprint: WorkspaceBlueprint
    let plan: Plan
    var callStatus: [ResearchCall.ID: Status] = [:]
    var fileStatus: [WorkspaceFile.ID: Status] = [:]
    var result: PlanWorkspace?
    var error: String?

    init(plan: Plan) {
        self.plan = plan
        blueprint = WorkspaceBlueprint(folderName: plan.name, calls: [], files: [])
    }

    var totalSteps: Int { blueprint.calls.count + blueprint.files.count }
    var doneSteps: Int {
        callStatus.values.filter { $0 == .done }.count + fileStatus.values.filter { $0 == .done }.count
    }
    var progress: Double { totalSteps == 0 ? 0 : Double(doneSteps) / Double(totalSteps) }
    var isWriting: Bool { !fileStatus.isEmpty }

    var currentLine: String {
        if result != nil { return "Folder ready" }
        if blueprint.calls.isEmpty && blueprint.files.isEmpty { return "Choosing what this plan needs…" }
        if let id = fileStatus.first(where: { $0.value == .running })?.key,
           let file = blueprint.files.first(where: { $0.id == id }) {
            return "Writing \(file.name)…"
        }
        if let id = callStatus.first(where: { $0.value == .running })?.key,
           let call = blueprint.calls.first(where: { $0.id == id }) {
            return "Searching \(Self.engineName(call.engine))…"
        }
        return "Getting started…"
    }

    func run(with service: WorkspaceService) async {
        do {
            for try await event in service.build(plan) {
                withAnimation(Motion.snappy) {
                    switch event {
                    case .planned(let blueprint):
                        self.blueprint = blueprint
                    case .researching(let id): callStatus[id] = .running
                    case .researched(let id, let result, let duration):
                        callStatus[id] = .done
                        if let i = blueprint.calls.firstIndex(where: { $0.id == id }) {
                            if !result.isEmpty { blueprint.calls[i].result = result }
                            if duration > 0 { blueprint.calls[i].duration = duration }
                        }
                    case .writing(let id): fileStatus[id] = .running
                    case .wrote(let id, let summary):
                        fileStatus[id] = .done
                        if let i = blueprint.files.firstIndex(where: { $0.id == id }), !summary.isEmpty {
                            blueprint.files[i].summary = summary
                        }
                    case .finished(let workspace): result = workspace
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func engineName(_ engine: String) -> String {
        switch engine {
        case "google_flights": "Google Flights"
        case "google_hotels": "Google Hotels"
        case "google_maps": "Google Maps"
        case "google_shopping": "Google Shopping"
        default: "Google Search"
        }
    }
}
