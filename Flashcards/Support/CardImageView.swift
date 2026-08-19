import SwiftUI

/// A card's picture, loaded from the server.
///
/// `AsyncImage` handles fetching and caching; the URL carries the owner's email
/// because the endpoint scopes pictures to the account that uploaded them.
struct CardImageView: View {
    let imageID: String
    var contentMode: ContentMode = .fit

    @Environment(LibraryStore.self) private var store

    var body: some View {
        AsyncImage(url: store.imageURL(imageID)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder(systemImage: "photo.badge.exclamationmark")
            case .empty:
                ZStack {
                    Theme.muted
                    ProgressView().controlSize(.small)
                }
            @unknown default:
                placeholder(systemImage: "photo")
            }
        }
        .accessibilityLabel("Card picture")
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Theme.muted
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}
