import SwiftUI

/// Sign in or create an account — the same RecallCards account as the
/// website. The server address sits here too, because on a phone there is no
/// Vite proxy to make `/api/...` resolve.
struct SignInView: View {
    @Environment(ServerSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(LibraryStore.self) private var store

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: Self { self }
    }

    private enum Field: Hashable { case name, email, password, confirm }

    @State private var mode = Mode.signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var awaitingVerification = false
    @FocusState private var focus: Field?

    @State private var serverAddress = ""
    @State private var validationMessage: String?
    @State private var showingServerField = false
    @State private var showingDeveloperSignIn = false
    @State private var developerEmail = ""

    private static let passwordMinimum = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    accountForm
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
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Recall Cards")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { serverAddress = settings.baseURLString }
        .onChange(of: mode) {
            errorText = nil
            infoText = nil
            awaitingVerification = false
        }
        .alert("Developer sign-in", isPresented: $showingDeveloperSignIn) {
            TextField("email", text: $developerEmail)
                .textInputAutocapitalization(.never)
            Button("Continue") { developerSignIn() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Identifies you by email only, like the web client's VITE_BYPASS_AUTH mode. Works only against a local backend started with RECALLCARDS_DEV_AUTH.")
        }
    }

    // MARK: - Account form

    private var accountForm: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode == .signUp {
                inputField("Name (optional)", text: $name, field: .name)
                    .textContentType(.givenName)
            }

            inputField("Email", text: $email, field: .email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            secureField(mode == .signUp ? "Password (at least \(Self.passwordMinimum) characters)" : "Password",
                        text: $password, field: .password)
                .textContentType(mode == .signUp ? .newPassword : .password)

            if mode == .signUp {
                secureField("Confirm password", text: $confirm, field: .confirm)
                    .textContentType(.newPassword)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let infoText {
                Label(infoText, systemImage: "envelope.badge")
                    .font(.callout)
                    .foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if auth.isAuthenticating {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isAuthenticating)

            HStack {
                if mode == .signIn {
                    Button("Forgot password?", action: forgotPassword)
                }
                Spacer()
                if awaitingVerification {
                    Button("Resend link", action: resendLink)
                }
            }
            .font(.footnote)

            Text(mode == .signIn
                 ? "The same account as recallcards.net."
                 : "We'll email you a link to activate your account. Open it, then sign in here.")
                .font(.footnote)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
    }

    private func inputField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .focused($focus, equals: field)
            .submitLabel(.next)
            .padding(12)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
    }

    private func secureField(_ title: String, text: Binding<String>, field: Field) -> some View {
        SecureField(title, text: text)
            .focused($focus, equals: field)
            .submitLabel(.go)
            .onSubmit(submit)
            .padding(12)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func submit() {
        errorText = nil
        infoText = nil
        guard ServerSettings.isValidEmail(trimmedEmail) else {
            errorText = "Enter a valid email address."
            return
        }
        if mode == .signUp {
            guard password.count >= Self.passwordMinimum else {
                errorText = "Use at least \(Self.passwordMinimum) characters for your password."
                return
            }
            guard password == confirm else {
                errorText = "The two passwords don't match."
                return
            }
        } else if password.isEmpty {
            errorText = "Enter your password."
            return
        }
        saveServerIfEdited()
        focus = nil

        Task {
            do {
                if mode == .signIn {
                    try await auth.logIn(email: trimmedEmail, password: password)
                    store.serverChanged()
                } else {
                    try await auth.signUp(email: trimmedEmail, password: password,
                                          name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                    mode = .signIn
                    confirm = ""
                    awaitingVerification = true
                    infoText = "Check \(trimmedEmail) for a link to activate your account, then sign in."
                }
            } catch AuthError.emailNotVerified {
                awaitingVerification = true
                errorText = AuthError.emailNotVerified.errorDescription
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func resendLink() {
        guard ServerSettings.isValidEmail(trimmedEmail) else { return }
        Task {
            do {
                try await auth.resendVerification(email: trimmedEmail)
                errorText = nil
                infoText = "A new link is on its way to \(trimmedEmail)."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func forgotPassword() {
        errorText = nil
        guard ServerSettings.isValidEmail(trimmedEmail) else {
            errorText = "Type your email above first, then tap Forgot password."
            return
        }
        saveServerIfEdited()
        Task {
            do {
                try await auth.forgotPassword(email: trimmedEmail)
                infoText = "If there's an account for \(trimmedEmail), a reset link is on its way. Choose a new password there, then sign in here."
            } catch {
                errorText = error.localizedDescription
            }
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
