import SwiftUI

/// The study session: one card at a time, flip to check, then mark it.
///
/// Marking posts to `/api/review`, which is what feeds the progress numbers and
/// the "needs review" flag — the same endpoint the web client uses.
struct StudyView: View {
    @Environment(LibraryStore.self) private var store

    /// Set only when the reader picks a collection explicitly; until then the
    /// session follows the account default. Owned here, not read from the
    /// store, so browsing another collection can't move a run in progress.
    @State private var pickedCollection: String?

    /// The collection this session is running over.
    ///
    /// Derived rather than assigned from a second `.task`: that arrangement
    /// let the task registered under the old id read the *new* value, start a
    /// request, and then be cancelled when the id caught up — one bogus
    /// "couldn't reach the server: cancelled" on every launch.
    private var activeCollection: String {
        pickedCollection ?? store.defaultCollection
    }

    @State private var deck = StudyDeck(cards: [], filter: .all, shuffled: false)
    @State private var session = StudySession()
    @State private var filter: StudyFilter = .all
    @State private var shuffled = false
    @State private var isFlipped = false
    @State private var isFinished = false
    @State private var showingCollectionPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.hasLoaded(activeCollection) {
                    loadingState
                } else if store.cards(in: activeCollection).isEmpty {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "No cards yet",
                        message: "Add cards to it from the Collections tab, or study a different one.",
                        actionTitle: "Choose a Collection",
                        action: { showingCollectionPicker = true }
                    )
                } else if isFinished {
                    SessionSummaryView(
                        session: session,
                        collectionName: activeCollection,
                        primary: SummaryAction(
                            title: flaggedTitle,
                            systemImage: "arrow.counterclockwise",
                            isEnabled: store.needsReviewCount(in: activeCollection) > 0,
                            action: { restart(with: .needsReview) }
                        ),
                        secondary: SummaryAction(
                            title: "Study the whole collection again",
                            systemImage: "square.stack",
                            action: { restart(with: .all) }
                        )
                    )
                } else if deck.isEmpty {
                    VStack(spacing: 0) {
                        filterPicker
                            .padding(.horizontal, 20)
                        EmptyStateView(
                            systemImage: "checkmark.circle",
                            title: emptyDeckTitle,
                            message: emptyDeckMessage
                        )
                    }
                } else {
                    sessionBody
                }
            }
            .background(Theme.background)
            .brandToolbar()
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Shuffle", isOn: $shuffled)
                        Divider()
                        Button("Restart session", systemImage: "arrow.counterclockwise") {
                            rebuildDeck()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCollectionPicker) {
                CollectionPickerSheet(selection: Binding(
                    get: { activeCollection },
                    set: { pickedCollection = $0 }
                ))
                .presentationDetents([.medium, .large])
            }
        }
        .task(id: activeCollection) {
            guard !activeCollection.isEmpty else { return }
            await store.load(collection: activeCollection)
            rebuildDeck()
        }
        .onChange(of: filter) { _, _ in rebuildDeck() }
        .onChange(of: shuffled) { _, _ in rebuildDeck() }
        .onChange(of: store.cards(in: activeCollection).map(\.term)) { _, _ in
            deck.reconcile(with: store.cards(in: activeCollection))
        }
    }

    // MARK: - Session

    private var sessionBody: some View {
        VStack(spacing: 20) {
            progressBar

            if let card = currentCard {
                FlipCardView(term: card.term,
                             definition: card.definition,
                             imageID: card.image,
                             needsReview: card.needsReview,
                             isFlipped: $isFlipped)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .id(card.term)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .gesture(
                        DragGesture(minimumDistance: 40)
                            .onEnded { value in
                                if value.translation.width < -40 { goForward() }
                                else if value.translation.width > 40 { goBack() }
                            }
                    )

                answerButtons(for: card)
            } else {
                EmptyStateView(systemImage: "checkmark.seal",
                               title: "Session complete",
                               message: "Every card in this filter has been answered.")
            }
        }
        .padding(.vertical, 16)
        .animation(.snappy, value: deck.currentTerm)
    }

    /// Which slice of the collection this run covers. Sits in the header rather
    /// than behind the toolbar menu: studying only what you got wrong is a
    /// normal thing to want, not an advanced setting.
    private var filterPicker: some View {
        Picker("Study", selection: $filter) {
            ForEach(StudyFilter.allCases) { option in
                Text(segmentLabel(for: option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    /// A count is more useful on a segment than a restatement of the name, and
    /// it shows at a glance whether the filter has anything in it.
    private func segmentLabel(for option: StudyFilter) -> String {
        let cards = store.cards(in: activeCollection)
        switch option {
        case .all: return "All \(cards.count)"
        case .needsReview: return "Review \(cards.filter(\.needsReview).count)"
        case .unseen: return "New \(cards.filter(\.isUnseen).count)"
        }
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Which collection you're in, always visible while studying —
                // and a shortcut to switch without leaving the session.
                Button {
                    showingCollectionPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(activeCollection)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Studying \(activeCollection)")
                .accessibilityHint("Opens the collection picker")

                Spacer(minLength: 8)

                Text("\(deck.position) of \(deck.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityLabel("Card \(deck.position) of \(deck.count), \(filter.rawValue)")
            }

            ProgressView(value: Double(deck.position), total: Double(max(deck.count, 1)))
                .tint(Theme.primary)
                .accessibilityHidden(true)

            filterPicker
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }

    private func answerButtons(for card: Card) -> some View {
        VStack(spacing: 14) {
            // Fixed height: without it the card grows and shrinks each time the
            // single Reveal button is replaced by the two answer buttons, and
            // the thing you are reading moves under your eyes.
            ZStack {
                if isFlipped {
                    HStack(spacing: 12) {
                        answerButton(title: "Needs review", systemImage: "arrow.counterclockwise",
                                     tint: Theme.accent, outcome: .incorrect, card: card)
                        answerButton(title: "Got it", systemImage: "checkmark",
                                     tint: Theme.success, outcome: .correct, card: card)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Button {
                        Haptics.light()
                        isFlipped = true
                    } label: {
                        Label("Show answer", systemImage: "eye")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(height: 52)

            HStack(spacing: 0) {
                secondaryControl(title: "Previous", systemImage: "chevron.left",
                                 disabled: deck.index == 0) {
                    goBack()
                }

                Spacer()

                secondaryControl(title: deck.isAtEnd ? "Finish" : "Skip",
                                 systemImage: deck.isAtEnd ? "flag.checkered" : "chevron.right",
                                 trailingIcon: true, disabled: false) {
                    if deck.isAtEnd {
                        finishSession()
                    } else {
                        goForward()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: isFlipped)
    }

    /// Text-only controls still need a real tap target and a colour that reads
    /// as interactive; muted grey text does neither.
    private func secondaryControl(title: String, systemImage: String,
                                  trailingIcon: Bool = false, disabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !trailingIcon { Image(systemName: systemImage) }
                Text(title)
                if trailingIcon { Image(systemName: systemImage) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(disabled ? Theme.mutedForeground.opacity(0.5) : Theme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func answerButton(title: String, systemImage: String, tint: Color,
                              outcome: ReviewOutcome, card: Card) -> some View {
        Button {
            answer(outcome, for: card)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading cards…").foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var flaggedTitle: String {
        let flagged = store.needsReviewCount(in: activeCollection)
        guard flagged > 0 else { return "Nothing flagged" }
        return "Review \(flagged) flagged card\(flagged == 1 ? "" : "s")"
    }

    private var emptyDeckTitle: String {
        switch filter {
        case .all: return "Nothing to study"
        case .needsReview: return "Nothing flagged"
        case .unseen: return "You've seen them all"
        }
    }

    private var emptyDeckMessage: String {
        switch filter {
        case .all: return "This collection has no cards yet."
        case .needsReview: return "Every card here is answered and cleared. Pick another slice above to keep going."
        case .unseen: return "You've opened every card in this collection at least once."
        }
    }

    // MARK: - Actions

    private var currentCard: Card? {
        deck.currentTerm.flatMap { store.card(for: $0, in: activeCollection) }
    }

    private func rebuildDeck() {
        deck = StudyDeck(cards: store.cards(in: activeCollection), filter: filter, shuffled: shuffled)
        session.reset()
        isFinished = false
        isFlipped = false
    }

    /// Starts a fresh run over a different slice of the same collection.
    private func restart(with newFilter: StudyFilter) {
        filter = newFilter
        // `onChange(of: filter)` rebuilds when the value actually changes;
        // do it here too so restarting the same filter still works.
        rebuildDeck()
    }

    private func answer(_ outcome: ReviewOutcome, for card: Card) {
        outcome == .correct ? Haptics.success() : Haptics.warning()
        session.record(term: card.term, outcome: outcome)
        Task { await store.recordReview(term: card.term, in: activeCollection, outcome: outcome) }

        if deck.isAtEnd {
            finishSession()
        } else {
            goForward()
        }
    }

    private func finishSession() {
        Haptics.success()
        withAnimation(.snappy) { isFinished = true }
    }

    private func goForward() {
        isFlipped = false
        deck.advance()
    }

    private func goBack() {
        isFlipped = false
        deck.goBack()
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    /// When there is an obvious next step, an empty screen is the best place to
    /// offer it.
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.mutedForeground)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                PrimaryActionButton(title: actionTitle, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
