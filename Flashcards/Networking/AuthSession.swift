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
    /// `VITE_BYPASS_AUTH` dev mode. No tokens.
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

/// What `/api/auth/login`, `/verify`, `/refresh` and `/reset-password` return.
struct TokenResponse: Decodable {
    struct User: Decodable {
        var email: String
        var name: String?
    }

    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
    var user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    var expiresAt: Date? {
        expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
    }
}
