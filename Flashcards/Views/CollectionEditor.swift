import SwiftUI

/// Creating and renaming a collection, on a real screen instead of inside an
/// alert — an alert gives you one cramped field, no room to say what the thing
/// is, and no room to explain why a name was rejected.
struct CollectionEditor: View {
    enum Mode: Identifiable {
        case create
        case rename(String)

        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let name): return "rename-\(name)"
            }
        }

        var existingName: String? {
            if case .rename(let name) = self { return name }
            return nil
        }
    }

    let mode: Mode

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSaving = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Spanish verbs", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                } header: {
                    Text("Name")
                } footer: {
                    Text(mode.existingName == nil
                         ? "A collection is a deck of cards you study together. You can move between collections at any time."
                         : "Renaming keeps every card and all of its review history.")
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.destructive)
                            .font(.callout)
                    }
                }
            }
            .themedScrollBackground()
            .navigationTitle(mode.existingName == nil ? "New Collection" : "Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.existingName == nil ? "Create" : "Rename", action: save)
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                name = mode.existingName ?? ""
                isFocused = true
            }
            .overlay {
                if isSaving { ProgressView().controlSize(.large) }
            }
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != mode.existingName
    }

    private func save() {
        // Caught here rather than after a round trip, so the field is still on
        // screen to correct.
        guard !store.collections.contains(trimmed) else {
            failure = "You already have a collection called \"\(trimmed)\"."
            return
        }
        failure = nil
        isSaving = true

        Task {
            let ok: Bool
            if let existing = mode.existingName {
                ok = await store.renameCollection(existing, to: trimmed)
            } else {
                ok = await store.createCollection(named: trimmed)
            }
            isSaving = false
            if ok { dismiss() }
        }
    }
}
