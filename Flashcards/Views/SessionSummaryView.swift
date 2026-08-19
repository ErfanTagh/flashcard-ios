import SwiftUI

/// One button on the round summary.
struct SummaryAction {
    let title: String
    var systemImage: String
    var isEnabled = true
    let action: () -> Void
}

/// Shown when a round ends — flashcards or quiz: how it went, and the two
/// things you'd plausibly want next. The pair of actions differs by mode, so
/// the caller supplies them.
struct SessionSummaryView: View {
    let session: StudySession
    let collectionName: String
    let primary: SummaryAction
    let secondary: SummaryAction

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Theme.muted, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: CGFloat(session.accuracy) / 100)
                            .stroke(Theme.brandGradient,
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(session.accuracy)%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("this round")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Accuracy this round")
                    .accessibilityValue("\(session.accuracy) percent")

                    Text(headline)
                        .font(.title3.weight(.semibold))
                    Label(collectionName, systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.top, 12)

                HStack(spacing: 12) {
                    tile(value: session.answered, label: "Answered", tint: Theme.primary)
                    tile(value: session.correct, label: "Got it", tint: Theme.success)
                    tile(value: session.incorrect, label: "Missed", tint: Theme.accent)
                }

                VStack(spacing: 12) {
                    Button(action: primary.action) {
                        Label(primary.title, systemImage: primary.systemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!primary.isEnabled)

                    Button(action: secondary.action) {
                        Label(secondary.title, systemImage: secondary.systemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }

    private var headline: String {
        if session.answered == 0 { return "Session ended" }
        if session.incorrect == 0 { return "Perfect round" }
        if session.accuracy >= 70 { return "Nicely done" }
        return "Worth another pass"
    }

    private func tile(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
