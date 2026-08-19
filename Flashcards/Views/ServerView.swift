import SwiftUI

/// Which backend the app talks to. Its own screen so the profile isn't
/// cluttered by something you set once.
struct ServerView: View {
    @Environment(ServerSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(LibraryStore.self) private var store

    @State private var draft = ""
    @State private var state: ConnectionState = .idle

    private enum ConnectionState: Equatable {
        case idle, checking
        case ok(String)
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                TextField(ServerSettings.defaultBaseURLString, text: $draft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ServerPresetMenu(text: $draft)
            }

            Section {
                Button("Save and test connection", action: apply)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)

                switch state {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Testing…").foregroundStyle(Theme.mutedForeground)
                    }
                case .ok(let detail):
                    Label(detail, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                case .failed(let detail):
                    Label(detail, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Theme.destructive)
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = settings.baseURLString }
    }

    private func apply() {
        guard let url = ServerSettings.normalisedURL(from: draft) else {
            state = .failed("That doesn't look like a URL.")
            return
        }
        settings.baseURLString = url.absoluteString
        draft = url.absoluteString
        store.serverChanged()
        state = .checking

        Task {
            guard let email = auth.email else { return }
            do {
                let auth = self.auth
                let probe = APIClient(baseURL: url) { await auth.validAccessToken() }
                let response = try await probe.collections(email: email)
                let count = response.collections.count
                state = .ok("Connected — \(count) collection\(count == 1 ? "" : "s")")
                await store.refreshAll()
            } catch {
                state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}
