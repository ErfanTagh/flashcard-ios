import SwiftUI

/// The typed-answer test, matching the website's `/quiz`: you are shown a term
/// and have to type its definition. Answers post to `/api/review` exactly as
/// flashcard answers do, so a quiz moves your progress and your review flags
/// the same way a study round does.
struct QuizView: View {
    let collection: String

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .intro
    @State private var questions: [Card] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var verdict: Verdict?
    /// Set when the reader overrules the grader for this question.
    @State private var override: Bool?
    @State private var isGrading = false
    @State private var session = StudySession()
    @FocusState private var isTyping: Bool

    private enum Phase { case intro, asking, finished }

    private struct Verdict: Equatable {
        let grade: QuizGrader.Grade
        let expected: String
    }

    /// What the answer will actually be recorded as: the grader's call unless
    /// the reader has said otherwise.
    private var countsAsCorrect: Bool {
        override ?? (verdict?.grade.countsAsCorrect ?? false)
    }

    var body: some View {
        Group {
            switch phase {
            case .intro:    intro
            case .asking:   asking
            case .finished: finished
            }
        }
        .background(Theme.background)
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Intro

    private var intro: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Theme.brandGradient)
                    Text("Test yourself")
                        .font(.title2.weight(.bold))
                    Label(collection, systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 10) {
                    rule("You'll see the term — type its definition")
                    rule("Capitals, punctuation and typos are forgiven")
                    rule("Long definitions are judged on meaning, not wording")
                    rule("You can overrule the marking on any question")
                    rule("Answers count towards your progress, like studying")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius,
                                                             style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

                if skippedCount > 0 {
                    Text("\(skippedCount) picture-only card\(skippedCount == 1 ? " is" : "s are") left out — there's nothing to type for them.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }

                if available.isEmpty {
                    Text("This collection has no cards to quiz.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                } else {
                    Button(action: start) {
                        Label("Start quiz — \(available.count) card\(available.count == 1 ? "" : "s")",
                              systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.foreground)
        }
    }

    // MARK: - Question

    private var asking: some View {
        VStack(spacing: 18) {
            header

            if let card = currentCard {
                VStack(spacing: 14) {
                    Text("WHAT DOES THIS MEAN?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mutedForeground)

                    Text(card.term)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .padding(.horizontal, 18)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge,
                                                                     style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)

                answerField

                if let verdict {
                    verdictBanner(verdict)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                Button(action: verdict == nil ? check : next) {
                    Group {
                        if isGrading {
                            ProgressView().tint(.white)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGrading
                          || (verdict == nil && typed.trimmingCharacters(in: .whitespaces).isEmpty))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 12)
        .animation(.snappy, value: verdict)
        .animation(.snappy, value: index)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Question \(index + 1) of \(questions.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Spacer()
                Text("Score \(session.correct)/\(session.answered)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.mutedForeground)
            }
            ProgressView(value: Double(index + 1), total: Double(max(questions.count, 1)))
                .tint(Theme.primary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
    }

    private var answerField: some View {
        TextField("Type the definition", text: $typed, axis: .vertical)
            .lineLimit(2...5)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isTyping)
            .submitLabel(verdict == nil ? .done : .next)
            .onSubmit { verdict == nil ? check() : next() }
            .disabled(verdict != nil)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius,
                                                         style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(fieldBorder, lineWidth: verdict == nil ? 1 : 2)
            )
            .padding(.horizontal, 20)
    }

    private var fieldBorder: Color {
        guard verdict != nil else { return Theme.border }
        return countsAsCorrect ? Theme.success : Theme.accent
    }

    private func verdictBanner(_ verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(headline(for: verdict), systemImage: countsAsCorrect
                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(countsAsCorrect ? Theme.success : Theme.accent)

            // Shown whenever the wording differed at all, so you can see what
            // you were being asked for and judge for yourself.
            if verdict.grade != .correct || !countsAsCorrect {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Expected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    Text(verdict.expected)
                        .font(.subheadline)
                        .foregroundStyle(Theme.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                override = !countsAsCorrect
                Haptics.light()
            } label: {
                Label(countsAsCorrect ? "No, I had it wrong" : "Actually, I was right",
                      systemImage: "arrow.2.squarepath")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((countsAsCorrect ? Theme.success : Theme.accent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func headline(for verdict: Verdict) -> String {
        if override != nil { return countsAsCorrect ? "Counted as correct" : "Counted as wrong" }
        switch verdict.grade {
        case .correct: return "Correct"
        case .close: return "Close — your call"
        case .incorrect: return "Not quite"
        }
    }

    private var actionTitle: String {
        if verdict == nil { return "Check answer" }
        return index == questions.count - 1 ? "See results" : "Next question"
    }

    // MARK: - Finished

    private var finished: some View {
        SessionSummaryView(
            session: session,
            collectionName: collection,
            primary: SummaryAction(title: "Take the quiz again", systemImage: "arrow.counterclockwise",
                                   action: start),
            secondary: SummaryAction(title: "Back to the collection", systemImage: "chevron.left",
                                     action: { dismiss() })
        )
    }

    // MARK: - Logic

    /// Picture-only cards are left out: there is no text to type, and the
    /// grading endpoint refuses them for the same reason.
    private var available: [Card] {
        store.cards(in: collection).filter(\.isQuizzable)
    }

    private var skippedCount: Int {
        store.cards(in: collection).count - available.count
    }

    private var currentCard: Card? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    private func start() {
        questions = available.shuffled()
        index = 0
        typed = ""
        verdict = nil
        override = nil
        session.reset()
        phase = .asking
        isTyping = true
    }

    private func check() {
        guard let card = currentCard, !isGrading else { return }
        isTyping = false
        isGrading = true

        Task {
            let grade = await store.gradeQuizAnswer(term: card.term, in: collection,
                                                    answer: typed, expected: card.definition)
            isGrading = false
            verdict = Verdict(grade: grade, expected: card.definition)
            override = nil
            grade.countsAsCorrect ? Haptics.success() : Haptics.warning()
        }
    }

    /// Commits the answer, then advances. Recording here rather than in
    /// `check` means an override changes the outcome instead of adding a
    /// second one — `/api/review` increments `seen` on every call.
    private func next() {
        commitAnswer()

        guard index < questions.count - 1 else {
            phase = .finished
            return
        }
        index += 1
        typed = ""
        verdict = nil
        override = nil
        isTyping = true
    }

    private func commitAnswer() {
        guard let card = currentCard, verdict != nil else { return }
        let outcome: ReviewOutcome = countsAsCorrect ? .correct : .incorrect
        session.record(term: card.term, outcome: outcome)
        Task { await store.recordReview(term: card.term, in: collection, outcome: outcome) }
    }

}
