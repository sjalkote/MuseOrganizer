import SwiftUI

/// Progress events while a plan folder is being built.
enum BuildEvent {
    case researching(ResearchCall.ID)
    case researched(ResearchCall.ID)
    case writing(WorkspaceFile.ID)
    case wrote(WorkspaceFile.ID)
    case finished(PlanWorkspace)
}

/// Builds a Google Drive folder for a plan. `WorkspaceServices.makeDefault()` picks the real
/// backend when one is configured (see docs/GOOGLE_WORKSPACE_SETUP.md).
protocol WorkspaceService {
    func build(_ blueprint: WorkspaceBlueprint) -> AsyncThrowingStream<BuildEvent, Error>
}

/// Demo implementation: replays the blueprint with realistic timing, no network.
struct SimulatedWorkspaceService: WorkspaceService {
    var speed: Double = 1

    func build(_ blueprint: WorkspaceBlueprint) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for call in blueprint.calls {
                    continuation.yield(.researching(call.id))
                    try await Task.sleep(for: .milliseconds(Int(min(call.duration, 1.2) * 550 / speed)))
                    continuation.yield(.researched(call.id))
                }
                for file in blueprint.files {
                    continuation.yield(.writing(file.id))
                    try await Task.sleep(for: .milliseconds(Int(700 / speed)))
                    continuation.yield(.wrote(file.id))
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

    func build(_ blueprint: WorkspaceBlueprint) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buildID: String?
                do {
                    var request = URLRequest(url: baseURL.appending(path: "plans/\(blueprint.planID.isEmpty ? "plan" : blueprint.planID)/workspace"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(BuildRequest(blueprint))
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
                            if let event = try Self.event(name, payload, blueprint) {
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

    private static func event(_ name: String, _ payload: Data, _ blueprint: WorkspaceBlueprint) throws -> BuildEvent? {
        let decoder = JSONDecoder()
        switch name {
        case "researching", "researched", "writing", "wrote":
            let step = try decoder.decode(Step.self, from: payload)
            guard let id = UUID(uuidString: step.id) else { return nil }
            switch name {
            case "researching": return .researching(id)
            case "researched": return .researched(id)
            case "writing": return .writing(id)
            default: return .wrote(id)
            }
        case "finished":
            let finished = try decoder.decode(Finished.self, from: payload)
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

private struct BuildRequest: Encodable {
    struct Call: Encodable { var id, engine, query: String }
    struct File: Encodable { var id, name, kind, summary: String; var sources: [String]; var content: ContentJSON? }

    var folderName, kind: String
    var members: [String]
    var context: [String: String]
    var calls: [Call]
    var files: [File]

    init(_ blueprint: WorkspaceBlueprint) {
        folderName = blueprint.folderName
        kind = blueprint.context["kind"] ?? "trip"
        members = blueprint.members
        context = blueprint.context
        calls = blueprint.calls.map { Call(id: $0.id.uuidString, engine: $0.engine, query: $0.query) }
        files = blueprint.files.map {
            File(id: $0.id.uuidString, name: $0.name, kind: $0.kind.rawValue, summary: $0.summary,
                 sources: $0.sources, content: ContentJSON($0.content))
        }
    }
}

/// `{columns, rows, footer}` for a sheet, `{blocks: [{type, text}]}` for a doc.
private struct ContentJSON: Codable {
    struct Block: Codable { var type, text: String }
    var columns: [String]?
    var rows: [[String]]?
    var footer: String?
    var blocks: [Block]?

    init?(_ content: FileContent) {
        switch content {
        case .sheet(let columns, let rows, let footer):
            self.columns = columns; self.rows = rows; self.footer = footer
        case .doc(let blocks):
            self.blocks = blocks.map {
                switch $0 {
                case .title(let text): Block(type: "title", text: text)
                case .heading(let text): Block(type: "heading", text: text)
                case .paragraph(let text): Block(type: "paragraph", text: text)
                case .bullet(let text): Block(type: "bullet", text: text)
                }
            }
        case .folder:
            return nil
        }
    }

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
private struct Step: Decodable { var id: String }
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

    let blueprint: WorkspaceBlueprint
    var callStatus: [ResearchCall.ID: Status] = [:]
    var fileStatus: [WorkspaceFile.ID: Status] = [:]
    var result: PlanWorkspace?
    var error: String?

    init(blueprint: WorkspaceBlueprint) { self.blueprint = blueprint }

    var totalSteps: Int { blueprint.calls.count + blueprint.files.count }
    var doneSteps: Int {
        callStatus.values.filter { $0 == .done }.count + fileStatus.values.filter { $0 == .done }.count
    }
    var progress: Double { totalSteps == 0 ? 0 : Double(doneSteps) / Double(totalSteps) }
    var isWriting: Bool { !fileStatus.isEmpty }

    var currentLine: String {
        if result != nil { return "Folder ready" }
        if let id = fileStatus.first(where: { $0.value == .running })?.key,
           let file = blueprint.files.first(where: { $0.id == id }) {
            return "Muse is writing \(file.name)…"
        }
        if let id = callStatus.first(where: { $0.value == .running })?.key,
           let call = blueprint.calls.first(where: { $0.id == id }) {
            return "Searching \(Self.engineName(call.engine))…"
        }
        return "Getting started…"
    }

    func run(with service: WorkspaceService) async {
        do {
            for try await event in service.build(blueprint) {
                withAnimation(Motion.snappy) {
                    switch event {
                    case .researching(let id): callStatus[id] = .running
                    case .researched(let id): callStatus[id] = .done
                    case .writing(let id): fileStatus[id] = .running
                    case .wrote(let id): fileStatus[id] = .done
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
