import Foundation
import Observation

enum AuthError: LocalizedError, Equatable {
    case noServer
    case emailNotVerified
    case badResponse(String)
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .noServer:
            return "Set a server address first."
        case .emailNotVerified:
            return "Confirm your email first. Open the link we sent you, then sign in."
        case .badResponse(let detail):
            return "The server sent something unexpected. \(detail)"
        case .denied(let detail):
            return detail
        }
    }
}

/// RecallCards' own accounts — the same ones the website uses
/// (flashcard-backend/accounts.py). Email and password go to `/api/auth/login`,
/// which answers with a short-lived access token and a refresh token. Both are
/// kept in the Keychain; the refresh token is single use and rotated on every
/// refresh.
///
/// New accounts are activated by an emailed link that opens the website.
@MainActor
@Observable
final class AuthService {
    private(set) var session: AuthSession?
    private(set) var isAuthenticating = false
    var errorMessage: String?

    @ObservationIgnored private let settings: ServerSettings
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private var refreshTask: Task<String?, Never>?

    private static let keychainAccount = "auth.session"

    init(settings: ServerSettings,
         keychain: KeychainStore = KeychainStore(),
         urlSession: URLSession = .shared) {
        self.settings = settings
        self.keychain = keychain
        self.urlSession = urlSession
        session = Self.loadSession(from: keychain)
    }

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    // MARK: - Sign in / sign up

    /// Throws `AuthError.emailNotVerified` for an account that isn't activated yet.
    func logIn(email: String, password: String) async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let tokens: TokenResponse = try await post("login", ["email": email, "password": password])
        store(tokens: tokens, fallbackEmail: email)
    }

    /// Creates the account and emails the activation link. Signing in works
    /// once the link has been opened.
    func signUp(email: String, password: String, name: String) async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let _: MessageResponse = try await post("signup", ["email": email, "password": password, "name": name])
    }

    func resendVerification(email: String) async throws {
        let _: MessageResponse = try await post("resend-verification", ["email": email])
    }

    func forgotPassword(email: String) async throws {
        let _: MessageResponse = try await post("forgot-password", ["email": email])
    }

    /// Local bypass mirroring the web client's dev mode. No tokens are minted,
    /// so it only works against a backend started with RECALLCARDS_DEV_AUTH.
    func logInAsDeveloper(email: String) {
        let session = AuthSession(email: email.lowercased(), name: "Developer",
                                  isDeveloperSession: true)
        self.session = session
        persist(session)
    }

    // MARK: - Logout

    /// Clears the local session and revokes the refresh token on the server.
    func logOut() async {
        let refreshToken = session?.refreshToken
        signOutLocally()
        refreshTask?.cancel()
        refreshTask = nil

        if let refreshToken {
            let _: MessageResponse? = try? await post("logout", ["refresh_token": refreshToken])
        }
    }

    // MARK: - Tokens

    /// A usable access token, refreshing first if it's about to expire.
    /// Returns nil for developer sessions and when the refresh fails.
    func validAccessToken() async -> String? {
        guard let session, !session.isDeveloperSession else { return nil }
        guard let token = session.accessToken else { return nil }
        guard session.needsRefresh else { return token }

        // Collapse concurrent callers onto one refresh: the refresh token is
        // single use, so a second refresh with the same one would fail.
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
            if self.session?.isExpired == true { signOutLocally() }
            return nil
        }

        do {
            let tokens: TokenResponse = try await post("refresh", ["refresh_token": refreshToken])
            var updated = session
            updated.accessToken = tokens.accessToken
            updated.expiresAt = tokens.expiresAt
            if let rotated = tokens.refreshToken { updated.refreshToken = rotated }
            self.session = updated
            persist(updated)
            return tokens.accessToken
        } catch AuthError.denied {
            // A refused refresh token is terminal — the user has to sign in again.
            signOutLocally()
            errorMessage = "Your session expired. Please sign in again."
            return nil
        } catch {
            // Offline or the server is down: keep the session and try later.
            return nil
        }
    }

    // MARK: - HTTP

    private struct MessageResponse: Decodable {
        var message: String?
    }

    private struct ErrorResponse: Decodable {
        var error: String?
        var code: String?
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        guard let base = settings.baseURL else { throw AuthError.noServer }
        var request = URLRequest(url: base.appendingPathComponent("api/auth/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthError.badResponse("Couldn't reach \(settings.displayHost). \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            if detail?.code == "email_not_verified" { throw AuthError.emailNotVerified }
            if (500...599).contains(http.statusCode), detail?.error == nil {
                throw AuthError.badResponse("Server error \(http.statusCode).")
            }
            throw AuthError.denied(detail?.error ?? "The server answered \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthError.badResponse(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func store(tokens: TokenResponse, fallbackEmail: String) {
        let session = AuthSession(
            email: (tokens.user?.email ?? fallbackEmail).lowercased(),
            name: tokens.user?.name,
            subject: tokens.user?.email,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
        self.session = session
        persist(session)
    }

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
        // A session from the Auth0 era has an access token the API no longer
        // accepts and a refresh token it never issued: start over.
        if !session.isDeveloperSession, session.subject?.contains("|") == true {
            keychain.delete(keychainAccount)
            return nil
        }
        // An expired access token is fine on launch as long as it can be
        // refreshed; without a refresh token the session is dead.
        if session.isExpired && session.refreshToken == nil && !session.isDeveloperSession {
            keychain.delete(keychainAccount)
            return nil
        }
        return session
    }
}
