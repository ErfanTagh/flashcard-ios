import SwiftUI

/// One-tap fill for the server field. Typing a URL on a phone keyboard is the
/// easiest place in this app to make a silent mistake.
struct ServerPresetMenu: View {
    @Binding var text: String

    var body: some View {
        Menu {
            ForEach(ServerSettings.presets) { preset in
                Button {
                    text = preset.urlString
                } label: {
                    Text(preset.name)
                    Text(preset.urlString)
                }
            }
        } label: {
            Label("Known servers", systemImage: "list.bullet.rectangle")
                .font(.subheadline)
        }
    }
}
