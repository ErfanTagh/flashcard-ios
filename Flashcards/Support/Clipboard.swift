import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Reading and writing the pasteboard, which is how JSON gets into this app:
/// nobody types a deck by hand on a phone.
enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    static func paste() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }

    static var hasText: Bool {
        #if canImport(UIKit)
        return UIPasteboard.general.hasStrings
        #else
        return false
        #endif
    }
}
