import SwiftUI

/// Live view of the folder being built: SerpApi searches first, then Muse writing each file.
struct BuildFolderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var plan: Plan
    var onOpenFolder: () -> Void

    @State private var session: BuildSession

    init(plan: Plan, blueprint: WorkspaceBlueprint, onOpenFolder: @escaping () -> Void) {
        self.plan = plan
        self.onOpenFolder = onOpenFolder
        _session = State(initialValue: BuildSession(blueprint: blueprint))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        header
                        research
                        writing.id("writing")
                        if session.result != nil { done.id("done") }
                    }
                    .padding(Space.m)
                    .padding(.bottom, Space.xl)
                }
                .onChange(of: session.isWriting) { if session.isWriting { withAnimation(Motion.smooth) { proxy.scrollTo("writing", anchor: .top) } } }
                .onChange(of: session.result) {
                    guard session.result != nil else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(Motion.smooth) { proxy.scrollTo("done", anchor: .bottom) }
                    }
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Plan folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.result == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .interactiveDismissDisabled(session.result == nil && session.error == nil)
            .sensoryFeedback(.success, trigger: session.result)
            .task {
                await session.run(with: model.workspaceService)
                if let ws = session.result { plan.workspace = ws }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        Panel {
            HStack(spacing: Space.m) {
                TintTile(symbol: session.result == nil ? "folder.fill" : "checkmark", tint: session.result == nil ? .stays : .activities, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.result == nil ? "Building \(session.blueprint.folderName)" : "Your folder is ready")
                        .font(.heading).foregroundStyle(Palette.ink)
                    Text(session.error ?? session.currentLine)
                        .font(.small)
                        .foregroundStyle(session.error == nil ? Palette.inkSecondary : Palette.critical)
                        .contentTransition(.opacity)
                }
            }
            .padding(.bottom, Space.m)
            ProgressView(value: session.progress)
                .tint(session.result == nil ? Palette.accent : Palette.positive)
            Text("\(session.doneSteps) of \(session.totalSteps) steps")
                .font(.small).figure()
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, Space.s)
        }
    }

    // MARK: Research (SerpApi)

    private var research: some View {
        Panel {
            PanelHeader(title: "Research", subtitle: "Live data from SerpApi", symbol: "magnifyingglass", tint: .flights)
                .padding(.bottom, Space.s)
            ForEach(Array(session.blueprint.calls.enumerated()), id: \.element.id) { i, call in
                let status = session.callStatus[call.id] ?? .queued
                HStack(alignment: .top, spacing: Space.m) {
                    StatusDot(status: status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BuildSession.engineName(call.engine)).font(.smallStrong).foregroundStyle(Palette.ink)
                        Text(call.query).font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: Space.s)
                    if status == .done {
                        Text(call.result).font(.small).figure().foregroundStyle(Palette.ink)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, Space.s)
                .opacity(status == .queued ? 0.5 : 1)
                .accessibilityElement(children: .combine)
                if i < session.blueprint.calls.count - 1 { Hairline(inset: 36) }
            }
        }
    }

    // MARK: Writing (Muse)

    private var writing: some View {
        Panel {
            PanelHeader(title: "Writing", subtitle: "Muse turns the research into files", symbol: "square.and.pencil", tint: .planner)
                .padding(.bottom, Space.s)
            ForEach(Array(session.blueprint.files.enumerated()), id: \.element.id) { i, file in
                let status = session.fileStatus[file.id] ?? .queued
                HStack(spacing: Space.m) {
                    TintTile(symbol: file.kind.symbol, tint: file.kind.tint, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name).font(.bodyRegular).foregroundStyle(Palette.ink)
                        Text(status == .done ? file.summary : file.kind.label)
                            .font(.small).foregroundStyle(Palette.inkSecondary)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    StatusDot(status: status)
                }
                .padding(.vertical, Space.s)
                .opacity(status == .queued ? 0.5 : 1)
                .accessibilityElement(children: .combine)
                if i < session.blueprint.files.count - 1 { Hairline(inset: 52) }
            }
        }
    }

    // MARK: Done

    private var done: some View {
        Panel(fill: Tint.activities.soft) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("\(session.blueprint.files.count) files in Google Drive")
                    .font(.bodyStrong).foregroundStyle(Palette.ink)
                Text("Built from \(session.blueprint.calls.count) searches. Share the link and everyone can open it, no app needed.")
                    .font(.small).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button { onOpenFolder() } label: { Label("Open folder", systemImage: "folder") }
                    .buttonStyle(.primary)
                ShareFolderButton(plan: plan)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct StatusDot: View {
    var status: BuildSession.Status

    var body: some View {
        Group {
            switch status {
            case .queued:
                Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.5).frame(width: 18, height: 18)
            case .running:
                ProgressView().controlSize(.small).frame(width: 18, height: 18)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.positive)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel(status == .done ? "Done" : status == .running ? "In progress" : "Waiting")
    }
}
