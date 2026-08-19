import SwiftUI

/// The opening animation: the brand tile drops in, the book draws itself,
/// the pages swing open, and the wordmark rises underneath.
///
/// Shown once per cold launch and timed to be over before anyone reads it —
/// roughly 1.9s including the fade out, and skippable by tapping.
struct LaunchIntroView: View {
    /// Called when the animation is finished and the app should take over.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tileScale: CGFloat = 0.72
    @State private var tileOpacity: Double = 0
    @State private var drawProgress: CGFloat = 0
    @State private var spread: Double = 34
    @State private var glow: Double = 0
    @State private var wordmarkOffset: CGFloat = 14
    @State private var wordmarkOpacity: Double = 0
    @State private var isLeaving = false
    @State private var hasStarted = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // A wash of the brand colours behind the mark, so the screen isn't
            // a flat rectangle while the logo is still drawing.
            RadialGradient(colors: [Theme.brandStart.opacity(0.28 * glow),
                                    Theme.background.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .blendMode(.plusLighter)

            VStack(spacing: 28) {
                RecallCardsLogo(size: 148, drawProgress: drawProgress, spread: spread)
                    .scaleEffect(tileScale)
                    .opacity(tileOpacity)
                    .shadow(color: Theme.brandStart.opacity(0.35 * glow), radius: 30, y: 12)

                VStack(spacing: 6) {
                    Text("Recall Cards")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.brandGradient)
                    Text("Study anything, anywhere")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }
                .offset(y: wordmarkOffset)
                .opacity(wordmarkOpacity)
            }
        }
        .opacity(isLeaving ? 0 : 1)
        .scaleEffect(isLeaving ? 1.06 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
    }

    private func run() async {
        if reduceMotion {
            // Same beats, no motion: settle immediately, hold briefly, leave.
            tileScale = 1
            tileOpacity = 1
            drawProgress = 1
            spread = 0
            glow = 1
            wordmarkOffset = 0
            wordmarkOpacity = 1
            try? await Task.sleep(for: .milliseconds(700))
            finish()
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            tileScale = 1
            tileOpacity = 1
            glow = 1
        }
        withAnimation(.easeOut(duration: 0.75).delay(0.12)) {
            drawProgress = 1
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.62)) {
            spread = 0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.72)) {
            wordmarkOffset = 0
            wordmarkOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(1550))
        finish()
    }

    private func finish() {
        guard !isLeaving else { return }
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            onFinish()
        }
    }
}

#Preview {
    LaunchIntroView(onFinish: {})
}
