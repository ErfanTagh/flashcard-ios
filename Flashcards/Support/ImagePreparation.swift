import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Turning what the photo picker hands back into something worth uploading.
///
/// Two problems with the raw bytes: an iPhone photo is HEIC, which browsers
/// can't display — so the web client would show a broken image for anything
/// added on a phone — and at full resolution it is several megabytes against a
/// 5MB server limit. Re-encoding to a downscaled JPEG fixes both.
enum ImagePreparation {
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.8
    static let mimeType = "image/jpeg"
    static let filename = "card.jpg"

    static func downscaledJPEG(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }

        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else {
            return image.jpegData(compressionQuality: jpegQuality)
        }

        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
        #else
        return data
        #endif
    }

    /// A SwiftUI image for bytes not yet uploaded, so the editor can show what
    /// was picked before it exists on the server.
    static func preview(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}
