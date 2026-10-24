import SwiftUI
import UIKit

/// Sends things back into the group's real chat app.
/// Huddle never posts on its own: every post here starts with a tap.
enum ChatBridge {
    /// URL that opens the app with a pre-filled message, or nil if the app has no such link.
    static func composeURL(for source: ChatSource, text: String) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch source {
        case .whatsapp: return URL(string: "whatsapp://send?text=\(encoded)")
        case .imessage: return URL(string: "sms:&body=\(encoded)")
        case .instagram: return URL(string: "instagram://direct-inbox")
        }
    }

    static func openURL(for source: ChatSource) -> URL? {
        switch source {
        case .whatsapp: URL(string: "whatsapp://")
        case .imessage: URL(string: "sms:")
        case .instagram: URL(string: "instagram://")
        }
    }

    /// Returns false when the app isn't installed, so the caller can fall back to the share sheet.
    @discardableResult
    static func open(_ url: URL?) -> Bool {
        guard let url, UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

/// "Post update to WhatsApp" button. Falls back to the system share sheet when the app isn't installed.
struct PostToChatButton: View {
    var plan: Plan
    var style: Style = .secondary
    @State private var showShare = false

    enum Style { case primary, secondary }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !ChatBridge.open(ChatBridge.composeURL(for: plan.source, text: plan.chatUpdate)) {
                showShare = true
            }
        } label: {
            Label("Post update to \(plan.chatName)", systemImage: "arrow.up.message")
        }
        .modify { button in
            switch style {
            case .primary: button.buttonStyle(.primary)
            case .secondary: button.buttonStyle(.secondary)
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [plan.chatUpdate])
                .presentationDetents([.medium, .large])
        }
        .accessibilityHint("Opens \(plan.source.rawValue) with a summary of the plan")
    }
}

struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    @ViewBuilder func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}
