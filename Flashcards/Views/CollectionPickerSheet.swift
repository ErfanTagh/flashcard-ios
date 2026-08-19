import SwiftUI

/// Picks which collection to study, without touching what the Collections tab
/// is browsing — deliberately not `CollectionsView`, which selects and manages.
struct CollectionPickerSheet: View {
    @Binding var selection: String

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.collections, id: \.self) { name in
                    Button {
                        selection = name
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).foregroundStyle(.primary)
                                if let count = store.count(for: name) {
                                    Text("\(count) card\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                            }
                            Spacer()
                            if name == selection {
                                Image(systemName: "checkmark").foregroundStyle(Theme.primary)
                            }
                        }
                    }
                }
            }
            .themedScrollBackground()
            .navigationTitle("Study which collection?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
