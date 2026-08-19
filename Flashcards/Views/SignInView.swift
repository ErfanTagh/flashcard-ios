import SwiftUI

/// Auth0 Universal Login, the same tenant and flow the web client uses. The
/// server address sits here too, because on a phone there is no Vite proxy to
/// make `/api/...` resolve.
struct SignInView: View {
    @Environment(ServerSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(LibraryStore.self) private var store

    @State private var serverAddress = ""
    @State private var validationMessage: String?
    @State private var showingServerField = false
    @State private var showingDeveloperSignIn = false
    @State private var developerEmail = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header

                    VStack(spacing: 14) {
                        Button(action: logIn) {
                            HStack(spacing: 8) {
                                if auth.isAuthenticating {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "lock.shield")
                                }
                                Text(auth.isAuthenticating ? "Opening Auth0…" : "Log in")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(auth.isAuthenticating)

                        Text("Opens Auth0 in a secure browser sheet. Sign up there if you don't have an account yet — it's the same login as the website.")
                            .font(.footnote)
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                    }

                    if !auth.isConfigured {
                        Label("Auth0 isn't configured — set Auth0Domain and Auth0ClientID in Info.plist.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.leading)
                    }

                    serverSection

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Developer sign-in") {
                        developerEmail = ""
                        showingDeveloperSignIn = true
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedForeground)
                }
                .padding(24)
            }
            .background(Theme.background)
            .navigationTitle("Recall Cards")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { serverAddress = settings.baseURLString }
        .alert("Developer sign-in", isPresented: $showingDeveloperSignIn) {
            TextField("email", text: $developerEmail)
                .textInputAutocapitalization(.never)
            Button("Continue") { developerSignIn() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Skips Auth0 and identifies you by email only, like the web client's VITE_BYPASS_AUTH mode. For local development.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            RecallCardsLogo(size: 96)
                .shadow(color: Theme.brandStart.opacity(0.3), radius: 18, y: 8)
            Text("Recall Cards")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.brandGradient)
            Text("Your cards, synced from your own server.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showingServerField.toggle() }
            } label: {
                HStack {
                    Label("Server", systemImage: "server.rack")
                    Spacer()
                    Text(settings.baseURLString)
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: showingServerField ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.mutedForeground.opacity(0.7))
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)

            if showingServerField {
                TextField(ServerSettings.defaultBaseURLString, text: $serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.muted,
                                in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit(saveServer)

                Text("Production is the same server the website uses. Local Docker works in the simulator only.")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)

                HStack {
                    ServerPresetMenu(text: $serverAddress)
                    Spacer()
                    Button("Save address", action: saveServer)
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Theme.card,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func saveServer() {
        guard let url = ServerSettings.normalisedURL(from: serverAddress) else {
            validationMessage = "That server address doesn't look like a URL."
            return
        }
        validationMessage = nil
        settings.baseURLString = url.absoluteString
        serverAddress = url.absoluteString
        store.serverChanged()
    }

    private func logIn() {
        saveServerIfEdited()
        Task { await auth.logIn() }
    }

    private func developerSignIn() {
        let email = developerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ServerSettings.isValidEmail(email) else {
            validationMessage = "Enter a valid email address."
            return
        }
        validationMessage = nil
        saveServerIfEdited()
        auth.logInAsDeveloper(email: email)
    }

    private func saveServerIfEdited() {
        guard showingServerField, serverAddress != settings.baseURLString else { return }
        saveServer()
    }
}
