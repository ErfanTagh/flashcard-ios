import SwiftUI
import UniformTypeIdentifiers

/// Builds a deck from JSON, which is mostly a way to have an AI write one.
///
/// The prompt is shown rather than merely offered for copying: it is the only
/// thing that explains what TOPIC means, and it is worth reading before it is
/// sent — the card count is in there.
struct ImportDeckView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var json = ""
    @State private var failure: String?
    @State private var isImporting = false
    @State private var showingFileImporter = false
    @State private var copiedPrompt = false

    /// The shape the API accepts, shown verbatim.
    private static let formatExample = """
    {
      "name": "Spanish Basics",
      "cards": [
        { "term": "hola", "definition": "hello" },
        { "term": "gracias", "definition": "thank you" }
      ]
    }
    """

    /// Matches the web client's prompt word for word, so a deck built on one
    /// and pasted into the other behaves the same.
    private static let aiPrompt = """
    Make a flashcard deck about TOPIC (for example: Spanish verbs).

    Reply with JSON only — no code fences, no explanation — in exactly this shape:

    {
      "name": "Short deck name",
      "cards": [
        { "term": "front of the card", "definition": "back of the card" }
      ]
    }

    Rules:
    - 20 cards, unless I ask for a different number.
    - "term" is what I will be shown and have to recall: a word, a phrase or a question. Under 80 characters.
    - "definition" is the answer. One or two sentences, under 300 characters, and do not restate the term inside it.
    - Every term must be unique.
    - Plain text only: no markdown, no HTML, no bullet points inside a field.
    - Write in the same language as this message unless I say otherwise.
    """

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                formatSection

                Section("Deck name") {
                    TextField("Taken from the JSON if left blank", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    if json.isEmpty {
                        Text("Nothing pasted yet")
                            .foregroundStyle(Theme.mutedForeground)
                            .font(.subheadline)
                    } else {
                        TextEditor(text: $json)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 140)
                    }

                    Button {
                        if let text = Clipboard.paste() {
                            json = text
                            failure = nil
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!Clipboard.hasText)

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Choose a .json file", systemImage: "folder")
                    }

                    if !json.isEmpty {
                        Button("Clear", role: .destructive) {
                            json = ""
                            failure = nil
                        }
                    }
                } header: {
                    Text("JSON")
                } footer: {
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }
            .themedScrollBackground()
            .navigationTitle("Import a Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: importDeck)
                        .disabled(json.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
                }
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.json, .plainText]) { result in
                load(from: result)
            }
            .overlay {
                if isImporting { ProgressView().controlSize(.large) }
            }
        }
    }

    private var promptSection: some View {
        Section {
            Text(Self.aiPrompt)
                .font(.caption)
                .foregroundStyle(Theme.foreground)
                .textSelection(.enabled)

            Button {
                Clipboard.copy(Self.aiPrompt)
                Haptics.light()
                copiedPrompt = true
            } label: {
                Label(copiedPrompt ? "Copied" : "Copy prompt",
                      systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Label("Prompt for an AI", systemImage: "sparkles")
        } footer: {
            Text("Replace TOPIC with the subject you want cards about — \"Spanish verbs\", \"the French Revolution\". The AI names the deck itself; you can change that below.")
        }
    }

    private var formatSection: some View {
        Section {
            Text(Self.formatExample)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
        } header: {
            Text("Expected format")
        } footer: {
            Text("front/back and question/answer work too, and a bare list of cards is accepted. Up to 500 cards.")
        }
    }

    private func load(from result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        // A file chosen outside the app's own container is security-scoped.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            failure = "That file couldn't be read as text."
            return
        }
        json = text
        failure = nil
        if name.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    private func importDeck() {
        failure = nil
        isImporting = true

        Task {
            let response = await store.importDeck(json: json, name: name)
            isImporting = false

            guard let response else {
                // The store reports the reason; surface it here instead, so it
                // appears against the JSON rather than as a detached alert.
                failure = store.errorMessage ?? "That deck couldn't be imported."
                store.errorMessage = nil
                return
            }
            Haptics.success()
            dismiss()
        }
    }
}
