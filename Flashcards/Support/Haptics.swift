import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Physical feedback for the study loop.
///
/// Answering a card is the one gesture repeated hundreds of times in this app,
/// and it happens while the reader is looking at the *next* card, not at the
/// button. A tap they can feel confirms it landed without asking them to check.
enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
