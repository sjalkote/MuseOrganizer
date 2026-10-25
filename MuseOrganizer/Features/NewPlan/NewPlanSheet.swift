import SwiftUI
import CoreImage.CIFilterBuiltins

/// Start a plan by adding the Planner to a group chat you already have.
struct NewPlanSheet: View {
    var onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "Japan Trip 2027"
    @State private var source: ChatSource = .whatsapp
    @State private var chat = "Japan crew"
    @State private var copied = false

    private let inviteURL = "https://huddle.app/j/japan-2027"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    field("Plan name", text: $name)

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Where does your group talk?").font(.smallStrong).foregroundStyle(Palette.ink)
                        VStack(spacing: 0) {
                            ForEach(Array(ChatSource.allCases.enumerated()), id: \.element) { index, s in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    source = s
                                } label: {
                                    HStack(spacing: Space.m) {
                                        Image(systemName: s.symbol).frame(width: 24)
                                        Text(s.rawValue).font(.bodyRegular)
                                        Spacer()
                                        if source == s {
                                            Image(systemName: "checkmark").font(.bodyStrong).foregroundStyle(Palette.accent)
                                        }
                                    }
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, Space.m)
                                    .frame(minHeight: 52)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(source == s ? .isSelected : [])
                                if index < ChatSource.allCases.count - 1 {
                                    Hairline(inset: 56)
                                }
                            }
                        }
                        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
                    }

                    field("Group chat", text: $chat)

                    invite

                    Label("Muse only reads this chat, and only replies when someone @mentions it.",
                          systemImage: "lock")
                        .font(.small)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(Space.m)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .safeAreaInset(edge: .bottom) {
                Button("Add Muse to \(chat.isEmpty ? "chat" : chat)") {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCreate()
                }
                .buttonStyle(.primary)
                .disabled(name.isEmpty || chat.isEmpty)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Palette.background)
            }
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label).font(.smallStrong).foregroundStyle(Palette.ink)
            TextField(label, text: text)
                .font(.bodyRegular)
                .padding(.horizontal, Space.m)
                .frame(minHeight: 52)
                .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
        }
    }

    private var invite: some View {
        HStack(alignment: .center, spacing: Space.m) {
            QRCode(text: inviteURL)
                .frame(width: 88, height: 88)
                .padding(Space.s)
                .background(.white, in: .rect(cornerRadius: Radius.s))
                .accessibilityLabel("Invite QR code")
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Or share an invite").font(.bodyStrong).foregroundStyle(Palette.ink)
                Text("Anyone in the chat can scan it to see the plan.")
                    .font(.small).foregroundStyle(Palette.inkSecondary)
                Button {
                    UIPasteboard.general.string = inviteURL
                    withAnimation(Motion.snappy) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copied = false } }
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                        .font(.smallStrong)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct QRCode: View {
    var text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
