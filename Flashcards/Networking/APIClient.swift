import Foundation

enum APIError: LocalizedError {
    case badURL
    /// The request was cancelled, almost always because SwiftUI tore down the
    /// task that started it. Normal control flow, never worth telling anyone.
    case cancelled
    case transport(String)
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "That server address isn't a valid URL."
        case .cancelled:
            return "The request was cancelled."
        case .transport(let detail):
            return "Couldn't reach the server. \(detail)"
        case .server(_, let message):
            return message
        case .decoding(let detail):
            return "The server sent something unexpected. \(detail)"
        }
    }
}

/// Talks to the Flask backend in `flashcard-backend/main.py`.
///
/// Two quirks of that API shape everything below:
///
/// 1. The caller is whoever the bearer token says. The email still travels in
///    bodies as `token` and in GETs as `email` or a path component, but the
///    API ignores it now: it reads the address out of the verified token. The
///    arguments below are kept because they are still part of the URL shape.
/// 2. Failures usually arrive as HTTP 200 with `{"status": 4xx, "error": ...}`
///    in the body, so the status code alone never tells you whether a write
///    succeeded. `send` checks both.
///
/// Attaching the access token on every call is what made the backend's move to
/// real authentication need no change here.
actor APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?

    init(baseURL: URL,
         session: URLSession = .shared,
         tokenProvider: @escaping @Sendable () async -> String? = { nil }) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Cards

    func cards(email: String, collection: String) async throws -> [Card] {
        let payload: CardsResponse = try await get("/api/cards", query: [
            "email": email, "collection": collection,
        ])
        return payload.cards
    }

    func progress(email: String, collection: String) async throws -> StudyProgress {
        try await get("/api/progress", query: ["email": email, "collection": collection])
    }

    /// Creates a card, or replaces the definition of one that already exists.
    /// The backend preserves review history across an overwrite.
    func addCard(email: String, collection: String, term: String, definition: String,
                 image: String?) async throws {
        // `image` is always sent, so clearing one is expressible.
        try await send("/api/sendwords", method: "POST", body: [
            "token": email, "word": term, "ans": definition, "collection": collection,
            "image": image ?? "",
        ])
    }

    /// Renames and/or redefines a card. `needsReview` is only sent when the
    /// caller means to change it — omitting it leaves the flag alone, which is
    /// what the backend's `editword` expects.
    func editCard(email: String, collection: String, oldTerm: String,
                  term: String, definition: String, image: String?? = nil,
                  needsReview: Bool? = nil) async throws {
        var body: [String: Any] = [
            "token": email, "oldword": oldTerm, "word": term,
            "ans": definition, "collection": collection,
        ]
        // Double optional: .none leaves the picture alone, .some(nil) clears it.
        if let image { body["image"] = image ?? "" }
        if let needsReview { body["needs_review"] = needsReview }
        try await send("/api/editword", method: "POST", body: body)
    }

    func deleteCard(email: String, collection: String, term: String) async throws {
        try await send("/api/delword/\(Self.escape(term))", method: "DELETE", body: [
            "token": email, "collection": collection,
        ])
    }

    /// Records one study answer and returns the card with its updated counters.
    func recordReview(email: String, collection: String, term: String,
                      outcome: ReviewOutcome) async throws -> Card? {
        let response: ReviewResponse = try await sendReturning("/api/review", method: "POST", body: [
            "token": email, "word": term, "outcome": outcome.rawValue, "collection": collection,
        ])
        return response.card
    }

    /// Grades a typed quiz answer server-side, so every client marks the same
    /// answer the same way.
    func gradeQuizAnswer(email: String, collection: String, term: String,
                         answer: String) async throws -> QuizGradeResponse {
        try await sendReturning("/api/quiz/grade", method: "POST", body: [
            "token": email, "word": term, "answer": answer, "collection": collection,
        ])
    }

    // MARK: - Importing

    /// Creates a deck from a JSON document.
    ///
    /// Takes the raw bytes rather than a parsed object, so untyped JSON never
    /// has to cross into this actor as `Any`. Parsing happens here, and a
    /// malformed document is reported before any request is made.
    func importDeck(email: String, jsonData: Data, name: String?) async throws -> DeckImportResponse {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        } catch {
            throw APIError.server(status: 400,
                                  message: "That isn't valid JSON. Check for a missing comma or bracket.")
        }

        var body: [String: Any] = ["token": email, "deck": parsed]
        if let name, !name.isEmpty { body["name"] = name }
        return try await sendReturning("/api/collections/import", method: "POST", body: body)
    }

    // MARK: - Images

    /// Uploads a picture and returns the id a card refers to it by.
    func uploadImage(email: String, data: Data, mimeType: String,
                     filename: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ text: String) { body.append(Data(text.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"token\"\r\n\r\n")
        append("\(email)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: try makeURL(path: "/api/images"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let responseData = try await perform(request)
        try throwIfErrorPayload(responseData)
        let payload: ImageUploadResponse = try decode(responseData)
        return payload.imageID
    }

    /// Where a stored picture can be fetched from. Not a request — this is
    /// handed to `AsyncImage`, which does its own loading and caching.
    nonisolated static func imageURL(base: URL, id: String, email: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.percentEncodedPath = components.percentEncodedPath + "/api/images/\(escape(id))"
        components.queryItems = [URLQueryItem(name: "email", value: email)]
        return components.url
    }

    // MARK: - Collections

    func collections(email: String) async throws -> CollectionsResponse {
        try await get("/api/collections/\(Self.escape(email))")
    }

    func collectionStats(email: String) async throws -> [String: Int] {
        let payload: StatsResponse = try await get("/api/collections/\(Self.escape(email))/stats")
        return payload.stats
    }

    func createCollection(email: String, name: String) async throws {
        try await send("/api/collections", method: "POST", body: [
            "token": email, "collection_name": name,
        ])
    }

    func deleteCollection(email: String, name: String) async throws {
        try await send("/api/collections/\(Self.escape(name))", method: "DELETE",
                       body: ["token": email])
    }

    func renameCollection(email: String, from oldName: String, to newName: String) async throws {
        try await send("/api/collections/\(Self.escape(oldName))/rename", method: "PUT", body: [
            "token": email, "new_collection_name": newName,
        ])
    }

    func setDefaultCollection(email: String, name: String) async throws {
        try await send("/api/collections/default", method: "POST", body: [
            "token": email, "collection_name": name,
        ])
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await perform(request)
        return try decode(data)
    }

    @discardableResult
    private func send(_ path: String, method: String, body: [String: Any]) async throws -> Data {
        let data = try await performWrite(path, method: method, body: body)
        try throwIfErrorPayload(data)
        return data
    }

    private func sendReturning<T: Decodable>(_ path: String, method: String,
                                             body: [String: Any]) async throws -> T {
        let data = try await performWrite(path, method: method, body: body)
        try throwIfErrorPayload(data)
        return try decode(data)
    }

    private func performWrite(_ path: String, method: String, body: [String: Any]) async throws -> Data {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    /// Joins an already-escaped path onto the base URL.
    ///
    /// `URL.appendingPathComponent` cannot be used here: it percent-encodes
    /// what it is given, so a component escaped by the caller gets escaped a
    /// second time — `My%20Deck` becomes `My%2520Deck`, and the server then
    /// looks up a collection whose name literally contains "%20". Assigning
    /// `percentEncodedPath` passes the escaping through untouched.
    private func makeURL(path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.percentEncodedPath = components.percentEncodedPath + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.badURL }
        return url
    }

    /// Escapes one path segment. Stricter than `.urlPathAllowed`, which leaves
    /// "/" alone — fine for a whole path, wrong for a single component: a card
    /// term or collection name containing a slash would otherwise split into
    /// two segments and 404.
    static func escape(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;,?:@&=+$#[]")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw APIError.server(status: http.statusCode,
                                      message: Self.errorMessage(in: data)
                                        ?? "Server returned status \(http.statusCode).")
            }
            return data
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    /// The backend reports most failures inside a 200 response body.
    private func throwIfErrorPayload(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let status = (object["status"] as? Int) ?? 200
        if status >= 400 {
            throw APIError.server(status: status,
                                  message: (object["error"] as? String) ?? "Request failed.")
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire types

struct CardsResponse: Decodable {
    var cards: [Card]
}

struct CollectionsResponse: Decodable {
    var collections: [String]
    var defaultCollection: String

    enum CodingKeys: String, CodingKey {
        case collections
        case defaultCollection = "default_collection"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let names = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        collections = names.isEmpty ? ["Default"] : names
        defaultCollection = try c.decodeIfPresent(String.self, forKey: .defaultCollection) ?? "Default"
    }
}

struct StatsResponse: Decodable {
    var stats: [String: Int]
}

private struct ReviewResponse: Decodable {
    var card: Card?
}

private struct ImageUploadResponse: Decodable {
    var imageID: String

    enum CodingKeys: String, CodingKey {
        case imageID = "image_id"
    }
}

struct DeckImportResponse: Decodable {
    var collection: String
    var imported: Int
    /// Non-fatal notes, such as a term that appeared twice.
    var warnings: [String] = []

    enum CodingKeys: String, CodingKey {
        case collection, imported, warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collection = try c.decode(String.self, forKey: .collection)
        imported = try c.decode(Int.self, forKey: .imported)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

struct QuizGradeResponse: Decodable {
    var grade: String
    var similarity: Double
    var expected: String

    var parsedGrade: QuizGrader.Grade {
        switch grade {
        case "correct": return .correct
        case "close": return .close
        default: return .incorrect
        }
    }
}
