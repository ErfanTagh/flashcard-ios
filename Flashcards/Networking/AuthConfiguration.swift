import Foundation

/// Auth0 settings, read from Info.plist so they can be changed without touching
/// code — the same three values the web client takes from `.env`
/// (`VITE_AUTH0_DOMAIN`, `VITE_AUTH0_CLIENT_ID`, `VITE_AUTH0_AUDIENCE`).
struct AuthConfiguration: Equatable {
    var domain: String
    var clientID: String
    /// Sent so Auth0 issues a JWT access token for the backend's API rather
    /// than an opaque one. Must match `API_AUDIENCE` in `main.py`.
    var audience: String?
    /// The custom URL scheme the login page redirects back to.
    var scheme: String

    static let scopes = "openid profile email offline_access"

    var isConfigured: Bool {
        !domain.isEmpty && !clientID.isEmpty && !scheme.isEmpty
    }

    /// Exact string that has to be listed in the Auth0 application's
    /// **Allowed Callback URLs**.
    var redirectURI: String { "\(scheme)://callback" }

    /// …and in **Allowed Logout URLs**.
    var logoutReturnURI: String { "\(scheme)://logout" }

    var authorizeURL: URL? { URL(string: "https://\(domain)/authorize") }
    var tokenURL: URL? { URL(string: "https://\(domain)/oauth/token") }
    var logoutURL: URL? { URL(string: "https://\(domain)/v2/logout") }
    var issuer: String { "https://\(domain)/" }

    static func fromBundle(_ bundle: Bundle = .main) -> AuthConfiguration {
        func string(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let audience = string("Auth0Audience")
        return AuthConfiguration(
            domain: string("Auth0Domain"),
            clientID: string("Auth0ClientID"),
            audience: audience.isEmpty ? nil : audience,
            scheme: string("Auth0Scheme")
        )
    }
}
