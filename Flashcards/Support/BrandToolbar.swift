import SwiftUI

/// The app mark in the navigation bar, mirroring the website's navbar — which
/// carries `recallcards-logo.svg` at the top left of every signed-in page.
struct BrandMark: View {
    /// Off in navigation bars: the mark shares that space with the page title,
    /// and the wordmark pushes it into the title on a narrow phone. The full
    /// lockup already leads the intro and the sign-in screen.
    var showsWordmark = false

    var body: some View {
        HStack(spacing: 8) {
            RecallCardsLogo(size: 28)
            if showsWordmark {
                Text("Recall Cards")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.brandGradient)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recall Cards")
    }
}

extension View {
    /// Adds the mark to the leading edge of a screen's navigation bar.
    func brandToolbar(showsWordmark: Bool = false) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandMark(showsWordmark: showsWordmark)
            }
        }
    }
}
