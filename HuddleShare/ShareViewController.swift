import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → Huddle" from Instagram, WhatsApp, Safari, or anywhere else.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await load() }
    }

    private func load() async {
        let (url, text) = await extractContent()
        let pageTitle = (extensionContext?.inputItems.first as? NSExtensionItem)
            .flatMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }
        let view = ShareView(
            url: url, text: text, suggestedTitle: Self.title(pageTitle: pageTitle, url: url, text: text), plans: SharedStore.plans(),
            onAdd: { [weak self] item in
                SharedStore.add(item)
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "Huddle", code: 0))
            }
        )
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Best guess at a human title: the page title, the first line of text, or the link's last path part.
    static func title(pageTitle: String?, url: URL?, text: String?) -> String {
        if let pageTitle, !pageTitle.isEmpty, !pageTitle.localizedCaseInsensitiveContains("not found") {
            return pageTitle.components(separatedBy: " • ").first ?? pageTitle
        }
        if let line = text?.components(separatedBy: .newlines).first, !line.isEmpty, !line.hasPrefix("http") {
            return String(line.prefix(60))
        }
        if let last = url?.pathComponents.last(where: { $0 != "/" }), last.count > 2 {
            let words = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
        return url?.host() ?? "Shared link"
    }

    /// Pulls the first link and/or text out of whatever was shared.
    private func extractContent() async -> (URL?, String?) {
        var url: URL?
        var text: String?
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
            }
            if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
            }
        }
        if url == nil, let text, let found = text.firstMatch(of: /https?:\/\/\S+/) { url = URL(string: String(found.output)) }
        return (url, text)
    }
}

struct ShareView: View {
    var url: URL?
    var text: String?
    var suggestedTitle: String
    var plans: [PlanSnapshot]
    var onAdd: (SharedItem) -> Void
    var onCancel: () -> Void

    @State private var title = ""
    @State private var planID = "japan"
    @State private var category = "Things to do"
    @State private var note = ""

    private var source: String { url == nil ? "Message" : SharedStore.source(for: url) }
    private let categories: [(String, String, Tint)] = [
        ("Flights", "airplane", .flights), ("Stays", "bed.double", .stays), ("Things to do", "ticket", .activities),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    preview
                    section("Which plan?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(plans) { plan in planChip(plan) }
                            }
                        }
                    }
                    section("What is it?") {
                        HStack(spacing: Space.s) {
                            ForEach(categories, id: \.0) { c in
                                Button { category = c.0 } label: {
                                    Label(c.0, systemImage: c.1)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(category == c.0 ? Color.white : c.2.strong)
                                        .padding(.horizontal, Space.m)
                                        .frame(minHeight: 40)
                                        .background(category == c.0 ? c.2.strong : c.2.soft, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    section("Note for the group") {
                        TextField("Why this one?", text: $note, axis: .vertical)
                            .padding(Space.m)
                            .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
                    }
                }
                .padding(Space.m)
            }
            .background(Palette.panel)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAdd(SharedItem(title: title.isEmpty ? "Shared link" : title, url: url?.absoluteString, text: text,
                                     source: source, sharedBy: "You", planID: planID, category: category, note: note))
                } label: {
                    Text("Add to \(plans.first { $0.id == planID }?.name ?? "plan")")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.accent, in: .capsule)
                }
                .padding(Space.m)
                .background(Palette.panel)
            }
            .navigationTitle("Add to NxT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
            .onAppear {
                if title.isEmpty { title = suggestedTitle }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("From \(source)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
            TextField("Title", text: $title)
                .font(.title3.weight(.semibold))
            if let url {
                Label(url.host() ?? url.absoluteString, systemImage: "link")
                    .font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
    }

    private func planChip(_ plan: PlanSnapshot) -> some View {
        let selected = plan.id == planID
        return Button { planID = plan.id } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: -6) {
                    ForEach(plan.memberNames.prefix(4), id: \.self) { name in
                        Text(String(name.prefix(1)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 26, height: 26)
                            .background(Palette.fillStrong, in: .circle)
                            .overlay(Circle().stroke(Palette.panel, lineWidth: 2))
                    }
                }
                Text(plan.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(plan.chatName).font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
            .padding(Space.m)
            .frame(width: 168, alignment: .leading)
            .background(selected ? Palette.accentFill : Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
            content()
        }
    }
}
