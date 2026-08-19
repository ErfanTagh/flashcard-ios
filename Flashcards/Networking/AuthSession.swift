import Foundation

/// A signed-in user plus the tokens that prove it.
///
/// `email` is the important field for day-to-day use: the backend keys every
/// card document on it, exactly as the web client does with `user.email`.
struct AuthSession: Codable, Equatable {
    var email: String
    var name: String?
    var pictureURL: URL?
    var subject: String?

    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?

    /// True for the local bypass that mirrors the web client's
    /// `VITE_BYPASS_AUTH` dev mode. No tokens, no Auth0 round trip.
    var isDeveloperSession = false

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return email
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Refreshed a minute early so a token can't expire mid-request.
    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

/// The `/oauth/token` response.
struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresIn: Int?
    var tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }

    var expiresAt: Date? {
        expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
    }
}

/// The claims this app reads out of an Auth0 ID token.
struct IDTokenClaims: Decodable {
    var email: String?
    var name: String?
    var nickname: String?
    var picture: String?
    var sub: String?
    var nonce: String?
    var iss: String?
    var exp: Double?

    /// Decodes the payload segment of a JWT.
    ///
    /// The signature is not verified, which is permitted here because the token
    /// came straight back from Auth0's token endpoint over TLS rather than
    /// through the redirect (OpenID Connect Core §3.1.3.7, RFC 8252 §7.1). The
    /// issuer and nonce are still checked by the caller. If ID tokens ever
    /// start arriving by any other route, this needs real JWKS validation.
    init?(jwt: String) {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2,
              let payload = Data(base64URLEncoded: String(segments[1])),
              let decoded = try? JSONDecoder().decode(IDTokenClaims.self, from: payload)
        else { return nil }
        self = decoded
    }

    var pictureURL: URL? { picture.flatMap(URL.init(string:)) }
}
