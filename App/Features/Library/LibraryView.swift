import FlashUpDomain
import SwiftUI

/// Deck list, global search and the way into everything the user owns.
struct LibraryView: View {
    @State private var model: LibraryModel
    @State private var isCreatingDeck = false
    @State private var newDeckName = ""
    @Environment(\.mediaStore) private var mediaStore
    @State private var importing = false

    init(library: any LibraryRepository) {
        _model = State(initialValue: LibraryModel(library: library))
    }

    var body: some View {
        List {
            if model.isSearching {
                searchSection
            } else {
                deckSection
                toolsSection
            }
        }
        .listStyle(.insetGrouped)
        // On the List, not on the Section inside it. A `navigationDestination` declared
        // within a lazy container is not registered with the enclosing NavigationStack, so
        // the deck rows highlighted on tap and then did nothing — the Library could not
        // open a deck at all.
        .navigationDestination(for: UUID.self) { deckID in
            DeckDetailView(library: model.library, deckID: deckID)
        }
        .screenCanvas()
        .safeAreaInset(edge: .top, spacing: 0) {
            AppBrandHeader {
                Button {
                    isCreatingDeck = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(
                            minWidth: Spacing.minimumTapTarget,
                            minHeight: Spacing.minimumTapTarget
                        )
                        .glassSurface(.prominent, cornerRadius: Spacing.cardCornerRadius)
                }
                .accessibilityLabel("library.new_deck")
                .accessibilityIdentifier("library.new_deck")
            }
        }
        .searchable(text: $model.filters.text, prompt: Text("library.search_prompt"))
        .onChange(of: model.filters.text) { Task { await model.runSearch() } }
        .alert("library.new_deck", isPresented: $isCreatingDeck) {
            TextField("library.deck_name", text: $newDeckName)
            Button("common.cancel", role: .cancel) { newDeckName = "" }
            Button("common.create") {
                let name = newDeckName
                newDeckName = ""
                Task { await model.createDeck(named: name) }
            }
        }
        .sheet(isPresented: $importing) {
            ImportFlowView(library: model.library, mediaStore: mediaStore) {
                Task { await model.refresh() }
            }
        }
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Sections

    private var deckSection: some View {
        Section("library.decks") {
            if model.decks.isEmpty {
                EmptyStateRow(
                    title: "library.empty.title",
                    message: "library.empty.message",
                    systemImage: "books.vertical"
                )
            }
            ForEach(model.decks) { summary in
                NavigationLink(value: summary.deck.id) {
                    DeckSummaryLabel(summary: summary)
                }
                .accessibilityIdentifier("library.deck_row")
                .swipeActions {
                    Button("common.delete", role: .destructive) {
                        Task { await model.trash(summary.deck) }
                    }
                }
            }
        }
        .paperRows()
    }

    private var toolsSection: some View {
        Section("library.tools") {
            Button {
                importing = true
            } label: {
                Label("library.import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("library.import")

            NavigationLink {
                TrashView(library: model.library)
            } label: {
                Label("library.trash \(model.trashed.count)", systemImage: "trash")
            }
            .accessibilityIdentifier("library.trash")
        }
        .paperRows()
    }

    private var searchSection: some View {
        Section("library.results \(model.searchResults.count)") {
            if model.searchResults.isEmpty {
                EmptyStateRow(
                    title: "library.no_results.title",
                    message: "library.no_results.message",
                    systemImage: "magnifyingglass"
                )
            }
            ForEach(model.searchResults) { summary in
                NavigationLink {
                    NoteEditorView(library: model.library, deckID: summary.note.deckID, note: summary.note)
                } label: {
                    NoteSummaryLabel(summary: summary)
                }
            }
        }
        .paperRows()
    }
}

/// Deck row used inside a `List`.
struct DeckSummaryLabel: View {
    let summary: DeckSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.deck.name)
                .font(.body.weight(.medium))
            Text("deck.counts \(summary.totalCards) \(summary.dueCount) \(summary.newCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Note row used in deck detail, search and trash.
struct NoteSummaryLabel: View {
    let summary: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.note.front.asNoteSummary)
                .lineLimit(2)
            HStack(spacing: Spacing.tight) {
                Text(summary.note.type.rawValue.capitalized)
                Text("note.card_count \(summary.cardCount)")
                if summary.isNew { Text("note.badge_new") }
                if summary.dueCount > 0 { Text("note.badge_due \(summary.dueCount)") }
                if summary.isSuspended { Text("note.badge_suspended") }
                if summary.isBuried { Text("note.badge_buried") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Empty state that explains and offers a way forward, never a bare "no items".
struct EmptyStateRow: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: Spacing.tight) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.normal)
        .accessibilityElement(children: .combine)
    }
}
