import SwiftUI

/// The first two seconds: NxT's mark settles in, a soft shine passes over it, "what's next?" fades up,
/// then everything lifts away into Home. Same paper color as the launch screen and the app, so it blends
/// at both ends. Tap to skip; Reduce Motion gets a plain fade.
struct IntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markIn = false
    @State private var shine = false
    @State private var taglineIn = false
    @State private var leaving = false
    @State private var finished = false

    private let markSize: CGFloat = 132

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            VStack(spacing: Space.l) {
                NxTMark(size: markSize)
                    .overlay { shineBand }
                    .clipShape(.rect(cornerRadius: markSize * 0.225, style: .continuous))
                    .shadow(color: Palette.shadow.opacity(markIn ? 1 : 0), radius: 28, y: 14)
                    .scaleEffect(reduceMotion ? 1 : (leaving ? 1.06 : (markIn ? 1 : 0.72)))
                    .blur(radius: reduceMotion || markIn ? 0 : 10)
                    .opacity(markIn && !leaving ? 1 : 0)

                Text("what's next?")
                    .font(.system(.title3, design: .serif).italic())
                    .foregroundStyle(Palette.inkSecondary)
                    .opacity(taglineIn && !leaving ? 1 : 0)
                    .offset(y: reduceMotion || taglineIn ? 0 : 10)
            }
            .offset(y: reduceMotion || !leaving ? 0 : -12)
        }
        .contentShape(.rect)
        .onTapGesture { finish() }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: markIn)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NxT. What's next?")
        .accessibilityAddTraits(.isStaticText)
    }

    /// A diagonal band of light that crosses the mark once.
    private var shineBand: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: markSize * 0.45)
            .rotationEffect(.degrees(20))
            .offset(x: shine ? markSize * 1.1 : -markSize * 1.1)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .opacity(reduceMotion ? 0 : 1)
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.7, dampingFraction: 0.78)) { markIn = true }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeInOut(duration: 0.9)) { shine = true }
        withAnimation(.easeOut(duration: 0.5)) { taglineIn = true }
        try? await Task.sleep(for: .milliseconds(1050))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        onFinish()
    }
}

/// Shows the intro over the app on a cold launch, then fades the app up from slightly smaller,
/// so the hand-off feels like one motion.
struct IntroHost<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var showIntro = true
    @State private var revealed = false

    var body: some View {
        ZStack {
            content
                .scaleEffect(revealed ? 1 : 0.97)
                .opacity(revealed ? 1 : 0)
            if showIntro {
                IntroView {
                    withAnimation(.easeOut(duration: 0.55).delay(0.12)) { revealed = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        showIntro = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
