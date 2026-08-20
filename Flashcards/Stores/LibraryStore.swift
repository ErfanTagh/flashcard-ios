import Foundation
import Observation

/// The app's single source of truth for collections, cards and progress.
///
/// Cards are cached per collection rather than for one "current" collection,
/// because two screens want different ones at the same time: a study session
/// stays on the collection it started with while you browse another. It also
/// means switching collections shows the previous contents instead of blanking
/// while a fetch runs.
///
/// Every mutation goes to the server first and then refetches, because the
/// backend rewrites the whole card document on write (renames, review-history
/// merges) and a local guess would drift from it.
@MainActor
@Observable
final class LibraryStore {
    private(set) var collections: [String] = ["Default"]
    private(set) var defaultCollection = "Default"
    private(set) var counts: [String: Int] = [:]

    private(set) var cardsByCollection: [String: [Card]] = [:]
    private(set) var progressByCollection: [String: StudyProgress] = [:]

    private(set) var isLoading = false
    private(set) var isWorking = false
    var errorMessage: String?

    /// What the Collections tab is browsing. The study session tracks its own
    /// collection separately, so opening one here can't move a run in progress.
    private(set) var selectedCollection = "Default"

    private let settings: ServerSettings
    private let auth: AuthService
    private var client: APIClient?
    private var configuredFor: (url: String, email: String)?
    private var inFlight: [String: Task<Void, Never>] = [:]

    init(settings: ServerSettings, auth: AuthService) {
        self.settings = settings
        self.auth = auth
    }

    // MARK: - Derived

    /// The browsed collection's cards, for screens scoped to it.
    var cards: [Card] { cards(in: selectedCollection) }
    var progress: StudyProgress { progress(in: selectedCollection) }

    func cards(in collection: String) -> [Card] {
        cardsByCollection[collection] ?? []
    }

    func progress(in collection: String) -> StudyProgress {
        progressByCollection[collection] ?? .empty
    }

    func needsReviewCount(in collection: String) -> Int {
        cards(in: collection).filter(\.needsReview).count
    }

    func card(for term: String, in collection: String) -> Card? {
        cards(in: collection).first { $0.term == term }
    }

    func count(for collection: String) -> Int? {
        counts[collection]
    }

    /// True until a collection has been fetched even once, so a screen can tell
    /// "empty" apart from "not loaded yet".
    func hasLoaded(_ collection: String) -> Bool {
        cardsByCollection[collection] != nil
    }

    // MARK: - Loading

    func refreshAll() async {
        guard let client = resolveClient(), let email = auth.email else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.collections(email: email)
            collections = response.collections
            defaultCollection = response.defaultCollection
            if !collections.contains(selectedCollection) {
                // Assigning here would trigger `didSet` and a second fetch, so
                // set the backing value and let the load below cover it.
                setSelected(response.defaultCollection)
            }
            counts = (try? await client.collectionStats(email: email)) ?? counts
        } catch {
            report(error)
        }

        await loadCards()
    }

    func loadCards() async {
        await load(collection: selectedCollection)
    }

    /// Fetches one collection's cards and progress into the cache.
    ///
    /// Concurrent callers for the same collection share one fetch: at launch
    /// the tab's `refreshAll` and the study screen both ask for it, and firing
    /// two identical requests would just race to write the same cache entry.
    func load(collection: String) async {
        if let existing = inFlight[collection] {
            await existing.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(collection: collection)
        }
        inFlight[collection] = task
        await task.value
        inFlight[collection] = nil
    }

    private func performLoad(collection: String) async {
        guard let client = resolveClient(), let email = auth.email else { return }
        do {
            async let fetchedCards = client.cards(email: email, collection: collection)
            async let fetchedProgress = client.progress(email: email, collection: collection)
            let cards = try await fetchedCards
            let progress = try await fetchedProgress
            cardsByCollection[collection] = cards
            progressByCollection[collection] = progress
        } catch {
            report(error)
        }
    }

    // MARK: - Card mutations

    func addCard(term: String, definition: String, image: String? = nil) async -> Bool {
        await mutate { client, email in
            try await client.addCard(email: email, collection: self.selectedCollection,
                                     term: term, definition: definition, image: image)
        }
    }

    /// `image` is a double optional: `.none` leaves the existing picture alone,
    /// `.some(nil)` removes it.
    func updateCard(original: Card, term: String, definition: String,
                    image: String?? = nil) async -> Bool {
        await mutate { client, email in
            try await client.editCard(email: email, collection: self.selectedCollection,
                                      oldTerm: original.term, term: term,
                                      definition: definition, image: image)
        }
    }

    /// Uploads a picture and returns the id to attach to a card, or nil if the
    /// upload failed — the failure is reported, so the caller can just stop.
    func uploadImage(_ data: Data, mimeType: String, filename: String) async -> String? {
        guard let client = resolveClient(), let email = auth.email else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            return try await client.uploadImage(email: email, data: data,
                                                mimeType: mimeType, filename: filename)
        } catch {
            report(error)
            return nil
        }
    }

    /// URL for a card picture, for `AsyncImage` to load.
    func imageURL(_ id: String) -> URL? {
        guard let base = settings.baseURL, let email = auth.email else { return nil }
        return APIClient.imageURL(base: base, id: id, email: email)
    }

    func setNeedsReview(_ card: Card, _ needsReview: Bool) async -> Bool {
        await mutate { client, email in
            try await client.editCard(email: email, collection: self.selectedCollection,
                                      oldTerm: card.term, term: card.term,
                                      definition: card.definition, needsReview: needsReview)
        }
    }

    func deleteCard(_ card: Card) async -> Bool {
        await mutate { client, email in
            try await client.deleteCard(email: email, collection: self.selectedCollection,
                                        term: card.term)
        }
    }

    /// Records a study answer. Patches the one card locally rather than
    /// refetching, so the study session doesn't stall between answers, then
    /// recomputes progress in the background.
    func recordReview(term: String, in collection: String, outcome: ReviewOutcome) async {
        guard let client = resolveClient(), let email = auth.email else { return }
        do {
            let updated = try await client.recordReview(email: email, collection: collection,
                                                        term: term, outcome: outcome)
            if let updated,
               let index = cardsByCollection[collection]?.firstIndex(where: { $0.term == term }) {
                cardsByCollection[collection]?[index] = updated
            }
            if let fresh = try? await client.progress(email: email, collection: collection) {
                progressByCollection[collection] = fresh
            }
        } catch {
            report(error)
        }
    }

    /// Grades a quiz answer on the server, falling back to the identical local
    /// implementation when the server can't be reached or is too old to have
    /// the endpoint. Grading offline is worth more than grading consistently.
    func gradeQuizAnswer(term: String, in collection: String,
                         answer: String, expected: String) async -> QuizGrader.Grade {
        if let client = resolveClient(), let email = auth.email {
            do {
                let response = try await client.gradeQuizAnswer(email: email,
                                                                collection: collection,
                                                                term: term, answer: answer)
                return response.parsedGrade
            } catch {
                // Not surfaced: a grade still comes back, just locally.
            }
        }
        return QuizGrader.grade(answer: answer, expected: expected).grade
    }

    // MARK: - Collection mutations

    func createCollection(named name: String) async -> Bool {
        let created = await mutate(reloadCards: false) { client, email in
            try await client.createCollection(email: email, name: name)
        }
        if created {
            setSelected(name)
            await refreshAll()
        }
        return created
    }

    func renameCollection(_ oldName: String, to newName: String) async -> Bool {
        let renamed = await mutate(reloadCards: false) { client, email in
            try await client.renameCollection(email: email, from: oldName, to: newName)
        }
        if renamed {
            if selectedCollection == oldName { setSelected(newName) }
            await refreshAll()
        }
        return renamed
    }

    func deleteCollection(_ name: String) async -> Bool {
        let deleted = await mutate(reloadCards: false) { client, email in
            try await client.deleteCollection(email: email, name: name)
        }
        if deleted {
            if selectedCollection == name { setSelected("Default") }
            await refreshAll()
        }
        return deleted
    }

    func makeDefault(_ name: String) async -> Bool {
        let done = await mutate(reloadCards: false) { client, email in
            try await client.setDefaultCollection(email: email, name: name)
        }
        if done { defaultCollection = name }
        return done
    }

    // MARK: - Importing

    /// Creates a deck from pasted JSON. Returns nil on failure, having already
    /// recorded why in `errorMessage`.
    func importDeck(json: String, name: String) async -> DeckImportResponse? {
        guard let client = resolveClient(), let email = auth.email else { return nil }

        let cleaned = Self.strippingCodeFences(json)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else {
            errorMessage = "There's nothing to import."
            return nil
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await client.importDeck(email: email, jsonData: data,
                                                       name: trimmedName)
            await refreshAll()
            return response
        } catch {
            report(error)
            return nil
        }
    }

    /// Removes the ```json fence a model wraps its answer in despite being told
    /// not to. Cheaper than asking the reader to tidy it by hand.
    static func strippingCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        // Drop the opening fence along with any language tag on the same line.
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        } else {
            trimmed = String(trimmed.dropFirst(3))
        }
        if let closing = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<closing.lowerBound])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Plumbing

    /// Runs a write, surfaces any failure, and refetches on success.
    private func mutate(reloadCards: Bool = true,
                        _ work: (APIClient, String) async throws -> Void) async -> Bool {
        guard let client = resolveClient(), let email = auth.email else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await work(client, email)
            if reloadCards {
                await loadCards()
                counts = (try? await client.collectionStats(email: email)) ?? counts
            }
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Switches collections and loads the new one.
    func select(_ name: String) async {
        setSelected(name)
        // Loads even when the name is unchanged: opening the collection that
        // happens to already be selected must still fetch it, or the screen
        // shows an empty list for a collection that is not empty.
        await load(collection: name)
    }

    private func setSelected(_ name: String) {
        // No clearing: the cache keeps whatever was last fetched for the new
        // collection, so the list doesn't blink through empty on the way in.
        selectedCollection = name
    }

    /// Client is rebuilt whenever the server address or account changes. The
    /// token provider is a closure rather than a captured string so each
    /// request picks up a refreshed access token.
    private func resolveClient() -> APIClient? {
        guard let email = auth.email, let url = settings.baseURL else { return nil }
        let key = (url: url.absoluteString, email: email)
        if let configuredFor, configuredFor == key, let client { return client }
        let auth = self.auth
        let fresh = APIClient(baseURL: url) { await auth.validAccessToken() }
        client = fresh
        configuredFor = key
        return fresh
    }

    func serverChanged() {
        client = nil
        configuredFor = nil
        inFlight.removeAll()
    }

    private func report(_ error: Error) {
        // A cancelled request means the view that wanted it went away, not that
        // anything failed. Alerting on it is pure noise.
        if case .cancelled? = error as? APIError { return }
        if error is CancellationError { return }
        errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
