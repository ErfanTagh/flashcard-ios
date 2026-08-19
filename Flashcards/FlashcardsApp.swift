import SwiftUI

@main
struct FlashcardsApp: App {
    @State private var settings: ServerSettings
    @State private var auth: AuthService
    @State private var store: LibraryStore

    init() {
        let settings = ServerSettings()
        let auth = AuthService()
        _settings = State(initialValue: settings)
        _auth = State(initialValue: auth)
        _store = State(initialValue: LibraryStore(settings: settings, auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(auth)
                .environment(store)
                .tint(Theme.primary)
        }
    }
}
