import Foundation
import Observation

/// Where the app looks for the backend.
///
/// The web client relies on a Vite dev proxy and Auth0; on a phone there is no
/// proxy, so the host is a setting. It defaults to the port the local override
/// in `docker-compose.local.yml` publishes.
///
/// Who the user is lives in `AuthService`, not here — this type only knows the
/// address. The value is computed over a private stored property rather than
/// written from `didSet`, because `@Observable` does not support property
/// observers on the stored properties it rewrites.
@Observable
final class ServerSettings {
    /// The deployed backend — the same host the website talks to, where nginx
    /// proxies `/api/` through to Flask.
    static let defaultBaseURLString = "https://recallcards.net"

    /// Servers worth one tap instead of typing a URL on a phone keyboard.
    struct Preset: Identifiable, Hashable {
        let name: String
        let detail: String
        let urlString: String
        var id: String { urlString }
    }

    static let presets: [Preset] = [
        Preset(name: "Production",
               detail: "The deployed server the website uses",
               urlString: "https://recallcards.net"),
        Preset(name: "Local Docker",
               detail: "Simulator only — docker-compose.local.yml",
               urlString: "http://localhost:5055"),
    ]

    private enum Keys {
        static let baseURL = "server.baseURL"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private var storedBaseURLString: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedBaseURLString = defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURLString
    }

    var baseURLString: String {
        get { storedBaseURLString }
        set {
            storedBaseURLString = newValue
            defaults.set(newValue, forKey: Keys.baseURL)
        }
    }

    var baseURL: URL? { Self.normalisedURL(from: baseURLString) }

    /// Host alone, for summary rows where the full URL is noise.
    var displayHost: String { baseURL?.host ?? baseURLString }

    /// Accepts what people actually type: a bare host, a host:port, or a full
    /// URL, with or without a trailing slash.
    static func normalisedURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    static func isValidEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }
}
