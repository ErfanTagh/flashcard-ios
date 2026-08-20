import SwiftUI

/// Manage collections: create, rename, delete, choose the default, and switch.
///
/// Serves as both the Collections tab and the quick-switch sheet the Study and
/// Cards screens present — `onDone` is what distinguishes the two.
struct CollectionsView: View {
    /// Non-nil when shown modally: adds a Done button and dismisses on select.
    var onDone: (() -> Void)?

    @Environment(LibraryStore.self) private var store

    @State private var editorMode: CollectionEditor.Mode?
    @State private var showingImport = false
    @State private var deleteTarget: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.collections, id: \.self) { name in
                        row(for: name)
                    }
                } footer: {
                    Text("The Default collection can't be renamed or deleted — the backend reserves it.")
                }
            }
            .themedScrollBackground()
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onDone != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { onDone?() }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        BrandMark()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import a deck", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportDeckView()
            }
            .primaryAction("New Collection") { editorMode = .create }
            .sheet(item: $editorMode) { mode in
                CollectionEditor(mode: mode)
            }
            .refreshable { await store.refreshAll() }
            .confirmationDialog("Delete collection?",
                                isPresented: Binding(get: { deleteTarget != nil },
                                                     set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let target = deleteTarget
                    deleteTarget = nil
                    if let target { Task { _ = await store.deleteCollection(target) } }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget.map { "\"\($0)\" and every card in it will be deleted." } ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(for name: String) -> some View {
        Group {
            if onDone == nil {
                // As a tab, a collection opens into its cards.
                NavigationLink {
                    CardListView(collection: name)
                } label: {
                    label(for: name)
                }
            } else {
                // As a sheet, picking one switches and dismisses.
                Button {
                    Task {
                        await store.select(name)
                        onDone?()
                    }
                } label: {
                    label(for: name)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if name != "Default" {
                Button(role: .destructive) {
                    deleteTarget = name
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    editorMode = .rename(name)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(Theme.primary)
            }
        }
        // Swipe actions are invisible until you swipe. A long-press menu shows
        // the same three, named.
        .contextMenu {
            Button {
                editorMode = .rename(name)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(name == "Default")

            Button {
                Task { _ = await store.makeDefault(name) }
            } label: {
                Label("Make default", systemImage: "star")
            }
            .disabled(name == store.defaultCollection)

            Divider()

            Button(role: .destructive) {
                deleteTarget = name
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(name == "Default")
        }
        .swipeActions(edge: .leading) {
            if name != store.defaultCollection {
                Button {
                    Task { _ = await store.makeDefault(name) }
                } label: {
                    Label("Default", systemImage: "star")
                }
                .tint(Theme.accent)
            }
        }
    }

    private func label(for name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: name == store.selectedCollection ? "folder.fill" : "folder")
                .foregroundStyle(Theme.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).foregroundStyle(.primary)
                    if name == store.defaultCollection {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.muted, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let count = store.count(for: name) {
                        Text("\(count) card\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    // Only shown for collections already fetched — the stats
                    // endpoint returns totals, not review state.
                    let flagged = store.needsReviewCount(in: name)
                    if store.hasLoaded(name), flagged > 0 {
                        Text("\(flagged) to review")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer()

            // Marks the collection the Study tab is currently on.
            if name == store.selectedCollection {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primary)
            }
        }
    }
}
