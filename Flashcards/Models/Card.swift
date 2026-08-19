import Foundation

/// One flashcard, in the structured shape `/api/cards` returns.
///
/// The backend still understands the older "definition string with a
/// `FFFLASHBACKCARDS` sentinel" encoding, but every endpoint this app talks to
/// speaks the structured form, so nothing here has to know about the sentinel.
struct Card: Identifiable, Hashable, Codable {
    var term: String
    var definition: String
    /// Id of a picture stored on the server, shown with the definition. A card
    /// may have text, a picture, or both.
    var image: String?
    var seen: Int
    var correct: Int
    var incorrect: Int
    var needsReview: Bool
    var lastReviewed: String?

    /// The term is the key inside a collection, so it is the natural identity.
    var id: String { term }

    enum CodingKeys: String, CodingKey {
        case term, definition, image, seen, correct, incorrect
        case needsReview = "needs_review"
        case lastReviewed = "last_reviewed"
    }

    init(term: String, definition: String, image: String? = nil, seen: Int = 0,
         correct: Int = 0, incorrect: Int = 0, needsReview: Bool = false,
         lastReviewed: String? = nil) {
        self.term = term
        self.definition = definition
        self.image = image
        self.seen = seen
        self.correct = correct
        self.incorrect = incorrect
        self.needsReview = needsReview
        self.lastReviewed = lastReviewed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decodeIfPresent(String.self, forKey: .term) ?? ""
        definition = try c.decodeIfPresent(String.self, forKey: .definition) ?? ""
        image = try c.decodeIfPresent(String.self, forKey: .image)
        seen = try c.decodeIfPresent(Int.self, forKey: .seen) ?? 0
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        incorrect = try c.decodeIfPresent(Int.self, forKey: .incorrect) ?? 0
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        lastReviewed = try c.decodeIfPresent(String.self, forKey: .lastReviewed)
    }

    var isUnseen: Bool { seen == 0 }

    var hasImage: Bool { !(image ?? "").isEmpty }

    /// A picture-only card has nothing to type, so the quiz can't ask for it.
    var isQuizzable: Bool { !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var accuracy: Int {
        let attempts = correct + incorrect
        guard attempts > 0 else { return 0 }
        return Int((Double(correct) / Double(attempts) * 100).rounded())
    }

    static func preview(_ term: String, _ definition: String) -> Card {
        Card(term: term, definition: definition, seen: 3, correct: 2, incorrect: 1)
    }
}

/// Aggregate study statistics for one collection, from `/api/progress`.
struct StudyProgress: Codable, Equatable {
    var total = 0
    var studied = 0
    var unseen = 0
    var needsReview = 0
    var known = 0
    var attempts = 0
    var accuracy = 0
    var lastReviewed: String?

    enum CodingKeys: String, CodingKey {
        case total, studied, unseen, known, attempts, accuracy
        case needsReview = "needs_review"
        case lastReviewed = "last_reviewed"
    }

    static let empty = StudyProgress()
}

enum ReviewOutcome: String {
    case correct
    case incorrect
}
