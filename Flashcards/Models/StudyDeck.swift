import Foundation

/// Which subset of a collection a study session runs over.
enum StudyFilter: String, CaseIterable, Identifiable {
    case all = "All cards"
    case needsReview = "Needs review"
    case unseen = "Not studied"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .needsReview: return "exclamationmark.arrow.circlepath"
        case .unseen: return "sparkles"
        }
    }

    func matches(_ card: Card) -> Bool {
        switch self {
        case .all: return true
        case .needsReview: return card.needsReview
        case .unseen: return card.isUnseen
        }
    }
}

/// The ordered queue a study session walks through.
///
/// Kept separate from the network layer so the session survives refreshes: the
/// deck holds terms, and the current card is looked up from the store by term.
struct StudyDeck {
    private(set) var terms: [String]
    private(set) var index = 0

    init(cards: [Card], filter: StudyFilter, shuffled: Bool) {
        let matching = cards.filter(filter.matches).map(\.term)
        terms = shuffled ? matching.shuffled() : matching
    }

    var isEmpty: Bool { terms.isEmpty }
    var count: Int { terms.count }
    var currentTerm: String? { terms.indices.contains(index) ? terms[index] : nil }
    var isAtEnd: Bool { index >= terms.count - 1 }
    var position: Int { min(index + 1, count) }

    mutating func advance() {
        guard index < terms.count - 1 else { return }
        index += 1
    }

    mutating func goBack() {
        guard index > 0 else { return }
        index -= 1
    }

    /// Drops terms that no longer exist (deleted mid-session) and clamps the
    /// cursor so the session cannot point past the end.
    mutating func reconcile(with cards: [Card]) {
        let live = Set(cards.map(\.term))
        let survivingBefore = terms.prefix(index).filter(live.contains).count
        terms.removeAll { !live.contains($0) }
        index = min(survivingBefore, max(terms.count - 1, 0))
    }
}
