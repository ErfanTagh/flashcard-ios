import PhotosUI
import SwiftUI

/// The cards inside one collection: browse, search, add, edit, delete.
///
/// Pushed from `CollectionsView`, so it has no navigation stack or collection
/// picker of its own — you are here *because* you picked one.
struct CardListView: View {
    /// The collection to make current on the way in.
    let collection: String

    @Environment(LibraryStore.self) private var store

    @State private var searchText = ""
    @State private var filter: StudyFilter = .all
    @State private var editorTarget: CardEditor.Target?
    @State private var pendingDeletion: Card?

    var body: some View {
        Group {
            if store.cards.isEmpty && !store.isLoading {
                EmptyStateView(systemImage: "rectangle.stack.badge.plus",
                               title: "\(collection) is empty",
                               message: "A card has a term on the front and its definition on the back.",
                               actionTitle: "Add a Card") { editorTarget = .new }
            } else {
                list
            }
        }
        .navigationTitle(collection)
        // A large title, not an inline one. An inline centre title squeezes the
        // navigation bar until UIKit drops the back button's label and leaves a
        // bare chevron; moving the title below the bar gives "< Collections"
        // room to spell itself out. Keeping the system back button also keeps
        // the swipe-from-edge gesture, which a hand-rolled one would break.
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search terms and definitions")
        .primaryAction("Add Card") { editorTarget = .new }
        .sheet(item: $editorTarget) { target in
            CardEditor(target: target)
        }
        .confirmationDialog("Delete this card?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let card = pendingDeletion {
                    Task { _ = await store.deleteCard(card) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion.map { "\"\($0.term)\" will be removed from \(collection)." } ?? "")
        }
        .refreshable { await store.refreshAll() }
        // Entering a collection makes it the current one, which is also what
        // the Study tab studies.
        .task(id: collection) { await store.select(collection) }
    }

    private var list: some View {
        List {
            // Progress used to be its own tab. It belongs here: it is a
            // property of the collection you are looking at.
            if searchText.isEmpty, filter == .all {
                Section {
                    NavigationLink {
                        ProgressDashboardView()
                    } label: {
                        ProgressSummaryRow(progress: store.progress)
                    }

                    if !store.cards.isEmpty {
                        NavigationLink {
                            QuizView(collection: collection)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Test yourself")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Type the definitions from memory")
                                        .font(.caption)
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                            } icon: {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(Theme.brandGradient)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if store.cards.count > 1 {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(StudyFilter.allCases) { option in
                            Text(shortLabel(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if !filtered.isEmpty {
                Section {
                    ForEach(filtered) { card in
                        Button {
                            editorTarget = .existing(card)
                        } label: {
                            CardRow(card: card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the card for editing")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = card
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editorTarget = .existing(card)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.primary)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { _ = await store.setNeedsReview(card, !card.needsReview) }
                                } label: {
                                    Label(card.needsReview ? "Clear flag" : "Flag",
                                          systemImage: card.needsReview ? "checkmark.circle" : "flag")
                                }
                                .tint(card.needsReview ? Theme.success : Theme.accent)
                            }
                            // The same actions, but findable without guessing
                            // that the row swipes.
                            .contextMenu {
                                Button {
                                    editorTarget = .existing(card)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    Task { _ = await store.setNeedsReview(card, !card.needsReview) }
                                } label: {
                                    Label(card.needsReview ? "Clear review flag" : "Flag for review",
                                          systemImage: card.needsReview ? "checkmark.circle" : "flag")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    pendingDeletion = card
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("\(filtered.count) card\(filtered.count == 1 ? "" : "s")")
                }
            } else if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: filter.systemImage)
                            .font(.title2)
                            .foregroundStyle(Theme.mutedForeground)
                        Text(emptyFilterMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                        Button("Show all cards") { filter = .all }
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .themedScrollBackground()
    }

    private var filtered: [Card] {
        let matching = store.cards.filter(filter.matches)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return matching }
        return matching.filter {
            $0.term.lowercased().contains(query) || $0.definition.lowercased().contains(query)
        }
    }

    private var emptyFilterMessage: String {
        switch filter {
        case .all: return "This collection has no cards."
        case .needsReview: return "Nothing is flagged for review."
        case .unseen: return "You've studied every card here at least once."
        }
    }

    /// The study filters read as full sentences; a segmented control has room
    /// for a word, and a count is more use than a restatement.
    private func shortLabel(for option: StudyFilter) -> String {
        switch option {
        case .all: return "All \(store.cards.count)"
        case .needsReview: return "Review \(store.cards.filter(\.needsReview).count)"
        case .unseen: return "New \(store.cards.filter(\.isUnseen).count)"
        }
    }
}

struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            if let image = card.image, !image.isEmpty {
                CardImageView(imageID: image, contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(card.term)
                    .font(.headline)
                    .lineLimit(1)
                if card.needsReview {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                if card.isUnseen {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.primary.opacity(0.15), in: Capsule())
                }
            }
            Text(card.definition.isEmpty ? "Picture only" : card.definition)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(2)
                .italic(card.definition.isEmpty)
            if !card.isUnseen {
                Text("Seen \(card.seen) · \(card.accuracy)% correct")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground.opacity(0.7))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Add or edit one card.
struct CardEditor: View {
    enum Target: Identifiable {
        case new
        case existing(Card)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let card): return card.term
            }
        }

        var card: Card? {
            if case .existing(let card) = self { return card }
            return nil
        }
    }

    let target: Target

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var definition = ""
    @State private var isSaving = false

    /// The picture as it stands: an id already on the server, freshly picked
    /// bytes not yet uploaded, or nothing.
    @State private var existingImageID: String?
    @State private var pickedImage: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isPreparingImage = false

    @FocusState private var focusedOnTerm: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. ephemeral", text: $term, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1...3)
                        .focused($focusedOnTerm)
                } header: {
                    Label("Front — what you'll be asked", systemImage: "rectangle.portrait")
                }

                Section {
                    TextField("e.g. lasting for a very short time", text: $definition, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Label("Back — the answer", systemImage: "rectangle.portrait.fill")
                }

                Section {
                    imageRow
                } header: {
                    Label("Picture (optional)", systemImage: "photo")
                } footer: {
                    Text(hasImage
                         ? "Shown with the definition. A card can be a picture alone, with no text."
                         : "Saving to \(store.selectedCollection).")
                }
            }
            .themedScrollBackground()
            .navigationTitle(target.card == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                if let card = target.card {
                    term = card.term
                    definition = card.definition
                    existingImageID = card.image
                } else {
                    focusedOnTerm = true
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await prepare(item) }
            }
            .overlay {
                if isSaving {
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private var hasImage: Bool { pickedImage != nil || existingImageID != nil }

    /// A card needs a front, and something on the back — which may be a
    /// picture rather than words.
    private var canSave: Bool {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasImage
    }

    @ViewBuilder
    private var imageRow: some View {
        if let pickedImage, let image = ImagePreparation.preview(from: pickedImage) {
            preview(image)
        } else if let existingImageID {
            preview(nil, existingID: existingImageID)
        }

        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack {
                Label(hasImage ? "Replace picture" : "Add a picture", systemImage: "photo.badge.plus")
                Spacer()
                if isPreparingImage { ProgressView().controlSize(.small) }
            }
        }
        .disabled(isPreparingImage)

        if hasImage {
            Button("Remove picture", role: .destructive) {
                pickedImage = nil
                pickerItem = nil
                existingImageID = nil
            }
        }
    }

    @ViewBuilder
    private func preview(_ image: Image?, existingID: String? = nil) -> some View {
        Group {
            if let image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else if let existingID {
                CardImageView(imageID: existingID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func prepare(_ item: PhotosPickerItem) async {
        isPreparingImage = true
        defer { isPreparingImage = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ImagePreparation.downscaledJPEG(data) else {
            store.errorMessage = "That picture couldn't be read."
            return
        }
        pickedImage = prepared
    }

    private func save() {
        let newTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDefinition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true

        Task {
            // Upload first: without an id there is nothing to attach, and a
            // failed upload shouldn't silently save a card without its picture.
            var imageID = existingImageID
            if let pickedImage {
                guard let uploaded = await store.uploadImage(pickedImage,
                                                             mimeType: ImagePreparation.mimeType,
                                                             filename: ImagePreparation.filename) else {
                    isSaving = false
                    return
                }
                imageID = uploaded
            }

            let ok: Bool
            if let original = target.card {
                ok = await store.updateCard(original: original, term: newTerm,
                                            definition: newDefinition, image: .some(imageID))
            } else {
                ok = await store.addCard(term: newTerm, definition: newDefinition, image: imageID)
            }
            isSaving = false
            if ok { dismiss() }
        }
    }
}

/// The compact progress read-out at the top of the card list, standing in for
/// what used to be a whole tab. Tapping it pushes the full breakdown.
struct ProgressSummaryRow: View {
    let progress: StudyProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.muted, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(progress.accuracy) / 100)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(progress.accuracy)%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 46, height: 46)
            .animation(.snappy, value: progress.accuracy)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Progress")
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer()

            if progress.needsReview > 0 {
                Text("\(progress.needsReview)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accentForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        guard progress.total > 0 else { return "No cards yet" }
        if progress.attempts == 0 { return "\(progress.total) cards · not studied yet" }
        return "\(progress.studied) of \(progress.total) studied · \(progress.known) known"
    }
}
