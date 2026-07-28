import FlashUpDomain
import Foundation
import Observation

/// Screen state for the Library tab: decks, global search, and the trash.
@Observable
@MainActor
final class LibraryModel {
    let library: any LibraryRepository

    private(set) var decks: [DeckSummary] = []
    private(set) var searchResults: [NoteSummary] = []
    private(set) var trashed: [Note] = []
    var filters = SearchFilters()

    init(library: any LibraryRepository) {
        self.library = library
    }

    var isSearching: Bool { filters.isActive }

    func refresh() async {
        decks = await library.decks()
        trashed = await library.trashedNotes()
        await runSearch()
    }

    func runSearch() async {
        guard filters.isActive else {
            searchResults = []
            return
        }
        searchResults = await library.search(filters, now: Date())
    }

    func createDeck(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await library.createDeck(named: trimmed)
        await refresh()
    }

    func rename(_ deck: Deck, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await library.renameDeck(deck.id, to: trimmed)
        await refresh()
    }

    func trash(_ deck: Deck) async {
        await library.trashDeck(deck.id)
        await refresh()
    }

    func restore(_ note: Note) async {
        await library.restoreNote(note.id)
        await refresh()
    }

    func emptyTrash() async {
        await library.emptyTrash()
        await refresh()
    }
}
