import SwiftUI

/// One small button at the top of a plan: builds the Google Drive folder, then opens it.
struct FolderButton: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: Plan

    @State private var showConnect = false
    @State private var showBuild = false
    @State private var showFolder = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if plan.workspace != nil { showFolder = true }
            else if model.googleAccount == nil { showConnect = true }
            else { showBuild = true }
        } label: {
            // Icon only: sits in the nav bar, one tap away from anywhere on the plan.
            Image(systemName: plan.workspace == nil ? "folder.badge.plus" : "folder.fill")
                .foregroundStyle(Tint.stays.strong)
        }
        .accessibilityLabel(plan.workspace == nil ? "Build a Google Drive folder for this plan" : "Open the \(plan.workspace!.folderName) folder")
        .sheet(isPresented: $showConnect) {
            ConnectGoogleSheet {
                model.googleAccount = "Devin T"
                showConnect = false
                Task { try? await Task.sleep(for: .milliseconds(400)); showBuild = true }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBuild) {
            BuildFolderSheet(plan: plan, blueprint: Mock.blueprint(for: plan)) {
                showBuild = false
                Task { try? await Task.sleep(for: .milliseconds(400)); showFolder = true }
            }
        }
        .sheet(isPresented: $showFolder) {
            FolderView(plan: plan)
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
