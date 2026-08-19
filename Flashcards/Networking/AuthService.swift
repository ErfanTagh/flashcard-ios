import AuthenticationServices
import Foundation
import Observation
import UIKit

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case badResponse(String)
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Auth0 isn't configured. Set Auth0Domain and Auth0ClientID in Info.plist."
        case .cancelled:
            return "Login was cancelled."
        case .badResponse(let detail):
            return "Auth0 sent something unexpected. \(detail)"
        case .denied(let detail):
            return detail
        }
    }
}

/// Auth0 Universal Login, the same identity provider and tenant the web client
/// uses — Authorization Code with PKCE, run in `ASWebAuthenticationSession`.
///
/// Deliberately no third-party SDK: the flow is four requests, and this keeps
/// the project dependency-free.
@MainActor
@Observable
final class AuthService {
    private(set) var session: AuthSession?
    private(set) var isAuthenticating = false
    var errorMessage: String?

    let configuration: AuthConfiguration

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let presenter = WebAuthPresenter()
    @ObservationIgnored private var webAuthSession: ASWebAuthenticationSession?
    @ObservationIgnored private var refreshTask: Task<String?, Never>?

    private static let keychainAccount = "auth.session"

    init(configuration: AuthConfiguration = .fromBundle(),
         keychain: KeychainStore = KeychainStore(),
         urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.keychain = keychain
        self.urlSession = urlSession
        session = Self.loadSession(from: keychain)
    }

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }
    var isConfigured: Bool { configuration.isConfigured }

    // MARK: - Login

    func logIn() async {
        guard configuration.isConfigured else {
            errorMessage = AuthError.notConfigured.errorDescription
            return
        }
        guard !isAuthenticating else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let pkce = PKCEChallenge()
            let state = PKCEChallenge.randomURLSafeString(byteCount: 16)
            let nonce = PKCEChallenge.randomURLSafeString(byteCount: 16)

            let callback = try await presentAuthorizeSession(pkce: pkce, state: state, nonce: nonce)
            let code = try authorizationCode(from: callback, expectedState: state)
            let tokens = try await exchange(code: code, verifier: pkce.verifier)
            try store(tokens: tokens, expectedNonce: nonce)
        } catch AuthError.cancelled {
            // Backing out of the login sheet isn't an error worth alerting on.
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Local bypass mirroring the web client's dev mode. No tokens are minted,
    /// so it only works because the backend's card endpoints key on the email
    /// alone.
    func logInAsDeveloper(email: String) {
        let session = AuthSession(email: email.lowercased(), name: "Developer",
                                  isDeveloperSession: true)
        self.session = session
        persist(session)
    }

    // MARK: - Logout

    /// Clears the local session, then asks Auth0 to drop its own cookie so the
    /// next login actually prompts instead of silently reusing the SSO session.
    func logOut() async {
        let wasFederated = session?.isDeveloperSession == false
        session = nil
        keychain.delete(Self.keychainAccount)
        refreshTask?.cancel()
        refreshTask = nil

        guard wasFederated, configuration.isConfigured,
              let logoutURL = configuration.logoutURL,
              var components = URLComponents(url: logoutURL, resolvingAgainstBaseURL: false)
        else { return }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "returnTo", value: configuration.logoutReturnURI),
        ]
        guard let url = components.url else { return }

        _ = try? await presentWebAuth(url: url, callbackScheme: configuration.scheme,
                                      ephemeral: false)
    }

    // MARK: - Tokens

    /// A usable access token, refreshing first if it's about to expire.
    /// Returns nil for developer sessions and when the refresh fails.
    func validAccessToken() async -> String? {
        guard let session, !session.isDeveloperSession else { return nil }
        guard let token = session.accessToken else { return nil }
        guard session.needsRefresh else { return token }

        // Collapse concurrent callers onto one refresh.
        if let refreshTask { return await refreshTask.value }
        let task = Task<String?, Never> { [weak self] in
            await self?.performRefresh()
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> String? {
        guard let session, let refreshToken = session.refreshToken else {
            // Nothing to refresh with: an expired token means signed out.
            if self.session?.isExpired == true { signOutLocally() }
            return nil
        }

        do {
            let tokens = try await requestTokens(body: [
                "grant_type": "refresh_token",
                "client_id": configuration.clientID,
                "refresh_token": refreshToken,
            ])
            var updated = session
            updated.accessToken = tokens.accessToken
            updated.expiresAt = tokens.expiresAt
            // Auth0 only returns a new refresh token when rotation is on.
            if let rotated = tokens.refreshToken { updated.refreshToken = rotated }
            self.session = updated
            persist(updated)
            return tokens.accessToken
        } catch {
            // A rejected refresh token is terminal — the user has to log in again.
            signOutLocally()
            errorMessage = "Your session expired. Please log in again."
            return nil
        }
    }

    // MARK: - Flow steps

    private func presentAuthorizeSession(pkce: PKCEChallenge, state: String,
                                         nonce: String) async throws -> URL {
        guard let authorizeURL = configuration.authorizeURL,
              var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        else { throw AuthError.notConfigured }

        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: AuthConfiguration.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        if let audience = configuration.audience {
            items.append(URLQueryItem(name: "audience", value: audience))
        }
        components.queryItems = items

        guard let url = components.url else { throw AuthError.notConfigured }
        return try await presentWebAuth(url: url, callbackScheme: configuration.scheme,
                                        ephemeral: false)
    }

    private func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { throw AuthError.badResponse("No parameters in the callback.") }

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw AuthError.denied(value("error_description") ?? error)
        }
        // Guards against a callback being replayed from another login attempt.
        guard value("state") == expectedState else {
            throw AuthError.badResponse("State mismatch.")
        }
        guard let code = value("code") else {
            throw AuthError.badResponse("No authorization code.")
        }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> TokenResponse {
        try await requestTokens(body: [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code_verifier": verifier,
            "code": code,
            "redirect_uri": configuration.redirectURI,
        ])
    }

    private func requestTokens(body: [String: String]) async throws -> TokenResponse {
        guard let tokenURL = configuration.tokenURL else { throw AuthError.notConfigured }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["error_description"] as? String }
            throw AuthError.denied(detail ?? "Auth0 returned status \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.badResponse(error.localizedDescription)
        }
    }

    private func store(tokens: TokenResponse, expectedNonce: String) throws {
        guard let idToken = tokens.idToken, let claims = IDTokenClaims(jwt: idToken) else {
            throw AuthError.badResponse("No ID token, so there's no email to identify you by.")
        }
        guard claims.nonce == expectedNonce else {
            throw AuthError.badResponse("Nonce mismatch.")
        }
        guard claims.iss == configuration.issuer else {
            throw AuthError.badResponse("Unexpected token issuer.")
        }
        guard let email = claims.email?.lowercased(), !email.isEmpty else {
            throw AuthError.badResponse("Your Auth0 profile has no email address, which the card API needs.")
        }

        let session = AuthSession(
            email: email,
            name: claims.name ?? claims.nickname,
            pictureURL: claims.pictureURL,
            subject: claims.sub,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
        self.session = session
        persist(session)
    }

    // MARK: - Web session

    private func presentWebAuth(url: URL, callbackScheme: String,
                                ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: callbackScheme) { callback, error in
                if let error {
                    let code = (error as NSError).code
                    if code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.denied(error.localizedDescription))
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: AuthError.badResponse("Empty callback."))
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = ephemeral
            webAuthSession = session

            if !session.start() {
                continuation.resume(throwing: AuthError.badResponse("Couldn't open the login page."))
            }
        }
    }

    // MARK: - Persistence

    private func persist(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        keychain.save(data, for: Self.keychainAccount)
    }

    private func signOutLocally() {
        session = nil
        keychain.delete(Self.keychainAccount)
    }

    private static func loadSession(from keychain: KeychainStore) -> AuthSession? {
        guard let data = keychain.load(keychainAccount),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data)
        else { return nil }
        // An expired access token is fine on launch as long as it can be
        // refreshed; without a refresh token the session is dead.
        if session.isExpired && session.refreshToken == nil && !session.isDeveloperSession {
            keychain.delete(keychainAccount)
            return nil
        }
        return session
    }
}

/// Tells `ASWebAuthenticationSession` which window to present over.
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
