import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    /// Once per cold launch, not once per sign-in — `@State` on the root view
    /// lives as long as the process does.
    @State private var isIntroFinished = false

    var body: some View {
        ZStack {
            Group {
                if auth.isSignedIn {
                    MainTabView()
                } else {
                    SignInView()
                }
            }
            .animation(.default, value: auth.isSignedIn)
            .authErrorAlert()

            if !isIntroFinished {
                LaunchIntroView { isIntroFinished = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AuthService.self) private var auth

    var body: some View {
        // Three, following the shape of the data: a collection holds cards, so
        // cards live inside a collection rather than beside it. Progress sits
        // one level deeper still, inside the card list it describes.
        TabView {
            StudyView()
                .tabItem { Label("Study", systemImage: "rectangle.on.rectangle.angled") }

            CollectionsView()
                .tabItem { Label("Collections", systemImage: "folder") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        // Keyed on the account so switching users reloads rather than showing
        // the previous person's cards.
        .task(id: auth.email) {
            await store.refreshAll()
        }
        .errorAlert()
    }
}

/// One place to surface store failures, so no screen has to own an alert.
struct ErrorAlert: ViewModifier {
    @Environment(LibraryStore.self) private var store

    func body(content: Content) -> some View {
        content.alert("Something went wrong",
                      isPresented: Binding(get: { store.errorMessage != nil },
                                           set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

extension View {
    func errorAlert() -> some View { modifier(ErrorAlert()) }
}

/// Login failures surface here rather than inside `SignInView`, so a session
/// that expires mid-use still reports itself.
struct AuthErrorAlert: ViewModifier {
    @Environment(AuthService.self) private var auth

    func body(content: Content) -> some View {
        content.alert("Login problem",
                      isPresented: Binding(get: { auth.errorMessage != nil },
                                           set: { if !$0 { auth.errorMessage = nil } })) {
            Button("OK", role: .cancel) { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }
}

extension View {
    func authErrorAlert() -> some View { modifier(AuthErrorAlert()) }
}
