import Foundation

/// Decides whether a typed answer counts.
///
/// The web client compares the normalised strings for equality. That is right
/// for "Danke → Thanks" and useless for a forty-word definition, where nobody
/// reproduces the wording exactly and being told "wrong" teaches nothing. So
/// this grades on a scale and, whatever it decides, the reader can overrule it:
/// in self-study the only judge who matters is the person studying.
enum QuizGrader {
    enum Grade: Equatable {
        /// Identical, or near enough that the difference is a typo.
        case correct
        /// Recognisably the same answer, but not close enough to call it.
        case close
        case incorrect

        var countsAsCorrect: Bool { self == .correct }
    }

    /// Above this a difference is treated as a slip, not a wrong answer.
    static let correctThreshold = 0.9
    /// Below this the answers aren't really the same thing.
    static let closeThreshold = 0.55

    static func grade(answer: String, expected: String) -> (grade: Grade, similarity: Double) {
        let a = normalise(answer)
        let b = normalise(expected)

        guard !a.isEmpty, !b.isEmpty else { return (.incorrect, 0) }
        if a == b { return (.correct, 1) }

        // A ratio alone is too harsh on short answers: one slip in a six-letter
        // word scores 0.83 and would be marked wrong, while the same slip in a
        // sentence disappears into the average. Allow a fixed number of edits
        // instead, scaled to length.
        if let distance = editDistance(a, b), distance <= typoAllowance(for: max(a.count, b.count)) {
            return (.correct, 1 - Double(distance) / Double(max(a.count, b.count)))
        }

        let score = similarity(a, b)
        if score >= correctThreshold { return (.correct, score) }
        if score >= closeThreshold { return (.close, score) }
        return (.incorrect, score)
    }

    /// How many character edits still count as the right answer.
    private static func typoAllowance(for length: Int) -> Int {
        switch length {
        case ..<5: return 0      // "need" vs "seed" is a different word
        case ..<12: return 1
        default: return 2
        }
    }

    private static func editDistance(_ a: String, _ b: String) -> Int? {
        guard max(a.count, b.count) <= 120 else { return nil }
        return levenshtein(Array(a), Array(b))
    }

    /// Lowercases, drops punctuation, collapses whitespace, and ignores a
    /// leading article — "the principle of X" and "principle of X" are the same
    /// answer, and only one of them is what you happened to type.
    static func normalise(_ text: String) -> String {
        let stripped = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }
        var words = String(stripped).split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first, ["a", "an", "the"].contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// The better of two views of the same pair: how many words they share, and
    /// how close the raw characters are. Word overlap carries long answers,
    /// where order and filler vary; edit distance carries short ones, where a
    /// single typo would otherwise score zero.
    static func similarity(_ a: String, _ b: String) -> Double {
        max(wordOverlap(a, b), characterSimilarity(a, b))
    }

    /// F1 over the two word multisets — precision and recall together, so
    /// neither padding an answer nor omitting half of it scores well.
    private static func wordOverlap(_ a: String, _ b: String) -> Double {
        let left = a.split(separator: " ").map(String.init)
        let right = b.split(separator: " ").map(String.init)
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        var remaining = right.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var shared = 0
        for word in left where (remaining[word] ?? 0) > 0 {
            remaining[word]! -= 1
            shared += 1
        }
        guard shared > 0 else { return 0 }

        let precision = Double(shared) / Double(left.count)
        let recall = Double(shared) / Double(right.count)
        return 2 * precision * recall / (precision + recall)
    }

    /// 1 - (edit distance / length of the longer string). Skipped for long text,
    /// where the comparison is quadratic and word overlap is the better signal
    /// anyway.
    private static func characterSimilarity(_ a: String, _ b: String) -> Double {
        let maxLength = max(a.count, b.count)
        guard maxLength > 0, maxLength <= 120 else { return 0 }
        let distance = levenshtein(Array(a), Array(b))
        return 1 - Double(distance) / Double(maxLength)
    }

    /// Optimal string alignment distance — Levenshtein plus transposition.
    ///
    /// Plain Levenshtein charges two edits for swapping adjacent letters, so
    /// "thnaks" scores as far from "thanks" as a genuinely different word.
    /// Transposition is the commonest typing mistake there is; it should cost
    /// one.
    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1,        // deletion
                              d[i][j - 1] + 1,        // insertion
                              d[i - 1][j - 1] + cost) // substitution
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) // transposition
                }
            }
        }
        return d[a.count][b.count]
    }
}
