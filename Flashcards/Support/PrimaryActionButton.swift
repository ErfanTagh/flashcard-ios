import SwiftUI

/// The brand-gradient action button that floats above a list.
///
/// A toolbar "+" is easy to miss — it is small, monochrome, and competes with
/// the title. This states what it does.
struct PrimaryActionButton: View {
    let title: String
    var systemImage = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Theme.brandGradient, in: Capsule())
            .shadow(color: Theme.brandStart.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Places the action button over the bottom of a list. `safeAreaInset`
    /// rather than `overlay`, so the last row can still be scrolled clear of it.
    func primaryAction(_ title: String, systemImage: String = "plus",
                       action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, alignment: .trailing) {
            PrimaryActionButton(title: title, systemImage: systemImage, action: action)
                .padding(.trailing, 20)
                .padding(.bottom, 10)
        }
    }
}
