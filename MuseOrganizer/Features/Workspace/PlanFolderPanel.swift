import SwiftUI

/// Entry point on a plan: build a Google Drive folder, or open and share the one that exists.
struct PlanFolderPanel: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan

    @State private var showConnect = false
    @State private var showBuild = false
    @State private var showFolder = false

    private var blueprint: WorkspaceBlueprint { Mock.blueprint(for: plan) }

    var body: some View {
        Panel {
            if let ws = plan.workspace {
                built(ws)
            } else {
                notBuilt
            }
        }
        .sheet(isPresented: $showConnect) {
            ConnectGoogleSheet {
                model.googleAccount = "Devin T"
                showConnect = false
                Task { try? await Task.sleep(for: .milliseconds(400)); showBuild = true }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBuild) {
            BuildFolderSheet(plan: plan, blueprint: blueprint) {
                showBuild = false
                Task { try? await Task.sleep(for: .milliseconds(400)); showFolder = true }
            }
        }
        .sheet(isPresented: $showFolder) {
            FolderView(plan: plan)
        }
    }

    // MARK: Before

    private var notBuilt: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PanelHeader(title: "Plan folder", subtitle: "Everything in one Google Drive folder",
                        symbol: "folder.fill", tint: .stays)

            Text("SerpApi researches every detail, and Muse writes it up as Sheets and Docs your group can share.")
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: Space.s) {
                ForEach(blueprint.files) { file in
                    Label(file.name, systemImage: file.kind.symbol)
                        .font(.smallStrong)
                        .foregroundStyle(file.kind.tint.strong)
                        .padding(.horizontal, Space.s + 2)
                        .padding(.vertical, Space.xs + 2)
                        .background(file.kind.tint.soft, in: .capsule)
                }
            }

            Button {
                if model.googleAccount == nil { showConnect = true } else { showBuild = true }
            } label: {
                Label("Build folder in Google Drive", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.primary)

            Text("\(blueprint.calls.count) searches · \(blueprint.files.count) files · about 20 seconds")
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: After

    private func built(_ ws: PlanWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PanelHeader(title: ws.folderName,
                        subtitle: "Google Drive · \(ws.files.count) files · \(ws.builtAt.formatted(.relative(presentation: .named)))",
                        symbol: "folder.fill", tint: .stays)

            VStack(spacing: 0) {
                ForEach(Array(ws.files.prefix(3).enumerated()), id: \.element.id) { i, file in
                    HStack(spacing: Space.m) {
                        TintTile(symbol: file.kind.symbol, tint: file.kind.tint, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.bodyRegular).foregroundStyle(Palette.ink)
                            Text(file.kind.label).font(.small).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Space.s)
                    if i < 2 { Hairline(inset: 48) }
                }
            }

            Button { showFolder = true } label: {
                Label("Open folder", systemImage: "folder")
            }
            .buttonStyle(.primary)

            ShareFolderButton(plan: plan)
        }
    }
}

/// Shares the folder link into the group's real chat (WhatsApp / iMessage), falling back to the share sheet.
struct ShareFolderButton: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    @State private var showShare = false

    private var text: String {
        guard let ws = plan.workspace else { return "" }
        return "Here's our \(ws.folderName) folder: budget, itinerary, and everything we researched.\n\(ws.url.absoluteString)"
    }

    var body: some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            model.shareWorkspace(of: plan)
            if !ChatBridge.open(ChatBridge.composeURL(for: plan.source, text: text)) { showShare = true }
        } label: {
            if let to = plan.workspace?.sharedTo {
                Label("Shared to \(to) · share again", systemImage: "checkmark")
            } else {
                Label("Share to \(plan.chatName)", systemImage: "arrow.up.message")
            }
        }
        .buttonStyle(.secondary)
        .sheet(isPresented: $showShare) {
            ActivityView(items: [text]).presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Connect Google

struct ConnectGoogleSheet: View {
    var onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                TintTile(symbol: "person.3.fill", tint: .planner, size: 56)
                Image(systemName: "arrow.left.arrow.right").font(.bodyStrong).foregroundStyle(Palette.inkFaint)
                TintTile(symbol: "folder.fill", tint: .stays, size: 56)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Space.l)

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Connect Google Drive").font(.heading).foregroundStyle(Palette.ink)
                Text("Huddle builds one folder per plan in your Drive.").font(.bodyRegular).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Label("Only sees the files it creates", systemImage: "lock.fill")
                Label("You choose who gets the link", systemImage: "link")
                Label("Disconnect anytime in Apps", systemImage: "xmark.circle")
            }
            .font(.small)
            .foregroundStyle(Palette.ink)

            Spacer(minLength: 0)

            Button("Continue with Google", action: onConnect)
                .buttonStyle(.primary)
            Text("Demo mode: sign-in is simulated.")
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(Space.l)
        .background(Palette.panel)
    }
}
