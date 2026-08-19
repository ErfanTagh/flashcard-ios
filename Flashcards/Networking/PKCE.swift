import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636).
///
/// A public client can't keep a secret, so instead of one it sends a hash of a
/// random string when starting login and the string itself when redeeming the
/// code. This is the same S256 flow `@auth0/auth0-react` runs in the browser.
struct PKCEChallenge {
    let verifier: String
    let challenge: String
    let method = "S256"

    init() {
        verifier = Self.randomURLSafeString(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString()
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            // SecRandom only fails if the system entropy pool is unavailable;
            // fall back rather than trap, since a login attempt is recoverable.
            bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes the base64url used by JWT segments, re-adding the padding that
    /// the encoding strips.
    init?(base64URLEncoded string: String) {
        var text = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text.append("=") }
        self.init(base64Encoded: text)
    }
}
