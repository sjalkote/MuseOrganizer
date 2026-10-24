import SwiftUI

/// The finished Google Drive folder: who can see it, what's inside, where the data came from.
struct FolderView: View {
    @Environment(\.dismiss) private var dismiss
    var plan: Plan
    @State private var showDemoNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let ws = plan.workspace {
                    VStack(alignment: .leading, spacing: Space.m) {
                        header(ws)
                        Panel(padding: 0) {
                            ForEach(Array(ws.files.enumerated()), id: \.element.id) { i, file in
                                NavigationLink(value: file) {
                                    HStack(spacing: Space.m) {
                                        TintTile(symbol: file.kind.symbol, tint: file.kind.tint, size: 40)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.name).font(.bodyStrong).foregroundStyle(Palette.ink)
                                            Text(file.summary).font(.small).foregroundStyle(Palette.inkSecondary)
                                            if !file.sources.isEmpty {
                                                Text("From " + file.sources.joined(separator: ", "))
                                                    .font(.small).foregroundStyle(Palette.inkSecondary)
                                            }
                                        }
                                        Spacer(minLength: Space.s)
                                        Image(systemName: "chevron.right").font(.small).foregroundStyle(Palette.inkFaint)
                                    }
                                    .padding(Space.m)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.pressable)
                                if i < ws.files.count - 1 { Hairline(inset: 72) }
                            }
                        }
                        sourcesPanel(ws)
                        VStack(spacing: Space.s) {
                            Button { showDemoNote = true } label: {
                                Label("Open in Google Drive", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.primary)
                            ShareFolderButton(plan: plan)
                        }
                    }
                    .padding(Space.m)
                    .padding(.bottom, Space.xl)
                }
            }
            .background(Palette.canvas)
            .navigationTitle(plan.workspace?.folderName ?? "Folder")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkspaceFile.self) { FilePreviewView(file: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Demo folder", isPresented: $showDemoNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("In the demo the folder lives in Huddle. Once Google Drive is connected for real, this opens it in Drive.")
            }
        }
    }

    private func header(_ ws: PlanWorkspace) -> some View {
        Panel {
            HStack(spacing: Space.m) {
                TintTile(symbol: "folder.fill", tint: .stays, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Drive › Huddle").font(.small).foregroundStyle(Palette.inkSecondary)
                    Text(ws.folderName).font(.heading).foregroundStyle(Palette.ink)
                    Text("\(ws.files.count) files · built \(ws.builtAt.formatted(.relative(presentation: .named)))")
                        .font(.small).foregroundStyle(Palette.inkSecondary)
                }
            }
            Hairline().padding(.vertical, Space.m)
            HStack(spacing: Space.m) {
                AvatarStack(members: plan.members, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ws.sharedTo.map { "Shared to \($0)" } ?? "Only you so far")
                        .font(.smallStrong).foregroundStyle(Palette.ink)
                    Text("Anyone with the link can view").font(.small).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: "link").foregroundStyle(Palette.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sourcesPanel(_ ws: PlanWorkspace) -> some View {
        Panel {
            PanelHeader(title: "Where this came from", subtitle: "\(ws.calls.count) SerpApi searches", symbol: "magnifyingglass", tint: .flights)
                .padding(.bottom, Space.s)
            ForEach(ws.calls) { call in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BuildSession.engineName(call.engine)).font(.smallStrong).foregroundStyle(Palette.ink)
                        Text(call.query).font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    Text(call.result).font(.small).foregroundStyle(Palette.ink)
                }
                .padding(.vertical, Space.xs + 2)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - File preview

struct FilePreviewView: View {
    var file: WorkspaceFile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Label(file.kind.label, systemImage: file.kind.symbol)
                        .font(.smallStrong)
                        .foregroundStyle(file.kind.tint.strong)
                    if !file.sources.isEmpty {
                        Text("· from " + file.sources.joined(separator: ", "))
                            .font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                }
                switch file.content {
                case .sheet(let columns, let rows, let footer):
                    SheetPreview(columns: columns, rows: rows, footer: footer)
                case .doc(let blocks):
                    DocPreview(blocks: blocks)
                case .folder(let note):
                    Panel {
                        VStack(spacing: Space.s) {
                            Image(systemName: "tray").font(.title).foregroundStyle(Palette.inkFaint)
                            Text(note).font(.small).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                    }
                }
            }
            .padding(Space.m)
        }
        .background(Palette.canvas)
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SheetPreview: View {
    var columns: [String]
    var rows: [[String]]
    var footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(columns, id: \.self) { c in
                            Text(c).font(.smallStrong).foregroundStyle(Palette.ink).cell(header: true)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        let isTotal = row.first == "Total" || row.first?.hasPrefix("Average") == true
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value)
                                    .font(isTotal ? .smallStrong : .small)
                                    .figure()
                                    .foregroundStyle(Palette.ink)
                                    .cell(header: false, striped: i.isMultiple(of: 2))
                            }
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: Radius.s))
                .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.separator))
            }
            if let footer {
                Label(footer, systemImage: "info.circle")
                    .font(.smallStrong)
                    .foregroundStyle(Tint.activities.strong)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(Tint.activities.soft, in: .capsule)
            }
        }
    }
}

private extension View {
    func cell(header: Bool, striped: Bool = false) -> some View {
        self
            .lineLimit(1)
            .padding(.horizontal, Space.m)
            .frame(minWidth: 96, maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(header ? Tint.activities.soft : (striped ? Palette.panel : Palette.fill.opacity(0.5)))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }
}

private struct DocPreview: View {
    var blocks: [DocBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .title(let t):
                    Text(t).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).padding(.bottom, Space.xs)
                case .heading(let t):
                    Text(t).font(.bodyStrong).foregroundStyle(Palette.ink).padding(.top, Space.m)
                case .paragraph(let t):
                    Text(t).font(.bodyRegular).foregroundStyle(Palette.ink)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("•").foregroundStyle(Palette.inkSecondary)
                        Text(t).font(.bodyRegular).foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.separator))
    }
}
