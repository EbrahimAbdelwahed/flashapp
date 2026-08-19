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
    private(set) var errorMessage: String?
    var filters = SearchFilters()

    init(library: any LibraryRepository) {
        self.library = library
    }

    var isSearching: Bool { filters.isActive }

    func refresh() async {
        do {
            decks = try await library.decks()
            trashed = try await library.trashedNotes()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await runSearch()
    }

    func runSearch() async {
        guard filters.isActive else {
            searchResults = []
            return
        }
        do {
            searchResults = try await library.search(filters, now: Date())
            errorMessage = nil
        } catch {
            searchResults = []
            errorMessage = String(localized: "library.error.unavailable")
        }
    }

    func createDeck(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do { _ = try await library.createDeck(named: trimmed) } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await refresh()
    }

    func rename(_ deck: Deck, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do { try await library.renameDeck(deck.id, to: trimmed) } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await refresh()
    }

    func trash(_ deck: Deck) async {
        do { try await library.trashDeck(deck.id) } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await refresh()
    }

    func restore(_ note: Note) async {
        do { try await library.restoreNote(note.id) } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await refresh()
    }

    func emptyTrash() async {
        do { try await library.emptyTrash() } catch {
            errorMessage = String(localized: "library.error.unavailable")
            return
        }
        await refresh()
    }
}
