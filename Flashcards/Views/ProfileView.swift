import SwiftUI

/// Who you are and how to leave. Everything else that used to live here —
/// library counts, build version, "signed in with" — told you nothing you
/// could act on, so it's gone. The server moved behind one row, since it is
/// plumbing you touch once.
struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ServerSettings.self) private var settings
    @Environment(LibraryStore.self) private var store

    @State private var showingLogOut = false

    var body: some View {
        NavigationStack {
            List {
                if let session = auth.session {
                    Section {
                        identity(for: session)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    NavigationLink {
                        ServerView()
                    } label: {
                        LabeledContent("Server", value: settings.displayHost)
                    }
                }

                Section {
                    Button("Log out", role: .destructive) { showingLogOut = true }
                }
            }
            .themedScrollBackground()
            .brandToolbar()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Log out?", isPresented: $showingLogOut, titleVisibility: .visible) {
                Button("Log out", role: .destructive) {
                    Task {
                        await auth.logOut()
                        store.serverChanged()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your cards stay on the server.")
            }
        }
    }

    private func identity(for session: AuthSession) -> some View {
        VStack(spacing: 12) {
            avatar(for: session)

            VStack(spacing: 3) {
                Text(session.displayName)
                    .font(.title3.weight(.semibold))
                Text(session.email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
            }

            // Only surfaced when it's true, because being in the bypass instead
            // of Auth0 changes what the app is doing.
            if session.isDeveloperSession {
                Text("Developer sign-in")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func avatar(for session: AuthSession) -> some View {
        Group {
            if let url = session.pictureURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.muted
                }
            } else {
                ZStack {
                    Theme.brandGradient
                    Text(String(session.displayName.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
    }
}
