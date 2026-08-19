import Foundation

/// What happened during one pass through a deck.
///
/// Separate from the per-card totals the backend keeps: those are lifetime
/// figures, this is "how did I just do". Keyed by term so going back and
/// re-answering a card corrects the tally instead of double-counting it.
struct StudySession {
    private(set) var outcomes: [String: ReviewOutcome] = [:]

    var answered: Int { outcomes.count }
    var correct: Int { outcomes.values.filter { $0 == .correct }.count }
    var incorrect: Int { outcomes.values.filter { $0 == .incorrect }.count }

    var accuracy: Int {
        guard answered > 0 else { return 0 }
        return Int((Double(correct) / Double(answered) * 100).rounded())
    }

    var isEmpty: Bool { outcomes.isEmpty }

    mutating func record(term: String, outcome: ReviewOutcome) {
        outcomes[term] = outcome
    }

    mutating func reset() {
        outcomes.removeAll()
    }
}
