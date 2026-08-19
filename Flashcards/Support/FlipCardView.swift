import SwiftUI

/// The term/definition card, flipped by tap like the web app's `FlipCard`.
///
/// Both faces are always in the hierarchy; the back is pre-rotated 180° so that
/// when the container turns, the visible face reads the right way round. Each
/// face hides itself past the halfway point so the two never bleed together.
struct FlipCardView: View {
    let term: String
    let definition: String
    var imageID: String?
    let needsReview: Bool
    @Binding var isFlipped: Bool

    private var angle: Double { isFlipped ? 180 : 0 }

    var body: some View {
        ZStack {
            face(text: term, caption: "Term", isBack: false)
                .opacity(isFlipped ? 0 : 1)

            face(text: definition, caption: "Definition", isBack: true)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
        .contentShape(Rectangle())
        .onTapGesture { isFlipped.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFlipped
                            ? "Definition: \(definition.isEmpty ? "a picture" : definition)"
                            : "Term: \(term)")
        .accessibilityHint("Double tap to flip the card")
        .accessibilityAddTraits(.isButton)
    }

    private func face(text: String, caption: String, isBack: Bool) -> some View {
        // The caption and the flip hint are overlaid on the padding rather than
        // stacked, so the text centres against the *card*, not against whatever
        // space those two happen to leave. A plain VStack with Spacers can't do
        // it: the ScrollView is greedy along its scroll axis and takes the whole
        // gap, pinning the text to the top.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Pictures belong to the answer, so they only appear on the
                    // back — showing one on the front would give the game away.
                    if isBack, let imageID, !imageID.isEmpty {
                        CardImageView(imageID: imageID)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: proxy.size.height * (text.isEmpty ? 1 : 0.6))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radius,
                                                        style: .continuous))
                    }

                    if !text.isEmpty || !isBack {
                        Text(text.isEmpty ? "—" : text)
                            .font(.system(size: isBack ? 24 : 30, weight: .semibold,
                                          design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                }
                // minHeight keeps short content centred; more than fits outgrows
                // it and scrolls as before.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack {
                Text(caption.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                if needsReview {
                    Label("Needs review", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(24)
        }
        .overlay(alignment: .bottom) {
            Text("Tap to flip")
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground.opacity(0.7))
                .padding(24)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .fill(isBack ? AnyShapeStyle(Theme.primary.opacity(0.10))
                             : AnyShapeStyle(Theme.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(needsReview ? Theme.accent.opacity(0.7) : Theme.border,
                              lineWidth: needsReview ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

#Preview {
    StatefulPreview()
}

private struct StatefulPreview: View {
    @State private var flipped = false
    var body: some View {
        FlipCardView(term: "ephemeral",
                     definition: "lasting for a very short time",
                     imageID: nil,
                     needsReview: true,
                     isFlipped: $flipped)
            .frame(height: 380)
            .padding()
    }
}
