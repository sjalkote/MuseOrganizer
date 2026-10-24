import SwiftUI

/// Progress events while a plan folder is being built.
enum BuildEvent {
    case researching(ResearchCall.ID)
    case researched(ResearchCall.ID)
    case writing(WorkspaceFile.ID)
    case wrote(WorkspaceFile.ID)
    case finished(PlanWorkspace)
}

/// Builds a Google Drive folder for a plan.
/// Swap `SimulatedWorkspaceService` for `GoogleWorkspaceService` once the backend is ready
/// (see docs/GOOGLE_WORKSPACE_SETUP.md).
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

/// Real implementation (not wired yet). The app calls our backend; the backend holds the
/// SerpApi key, the Muse Spark key, and the user's Google OAuth token, and streams progress back.
///
///   POST /plans/{id}/workspace           -> starts a build, returns a build id
///   GET  /builds/{buildId}/events (SSE)  -> researching / researched / writing / wrote / finished
///
/// The backend loop: Muse Spark plans the research as tool calls -> each tool call runs a
/// SerpApi engine -> Muse writes Sheets and Docs through the Drive, Sheets, and Docs APIs ->
/// the folder is shared by link with the group.
struct GoogleWorkspaceService: WorkspaceService {
    var baseURL: URL

    func build(_ blueprint: WorkspaceBlueprint) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: WorkspaceError.notConfigured) }
    }
}

enum WorkspaceError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "Google Drive isn't set up for this build yet." }
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
