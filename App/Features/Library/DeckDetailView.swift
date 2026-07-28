import FlashUpDomain
import SwiftUI

/// The notes inside one deck, with the filters of spec §A11.5.
struct DeckDetailView: View {
    let library: any LibraryRepository
    let deckID: UUID

    @State private var deck: Deck?
    @State private var notes: [NoteSummary] = []
    @State private var filters = SearchFilters()
    @State private var editingNote: Note?
    @State private var isCreating = false
    @State private var isExporting = false
    @State private var studying = false

    var body: some View {
        List {
            Section {
                Picker("filter.state", selection: $filters.state) {
                    ForEach(SearchFilters.State.allCases, id: \.self) { state in
                        Text(stateTitle(state)).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("deck.filter")
            }

            Section("deck.notes \(notes.count)") {
                if notes.isEmpty {
                    EmptyStateRow(
                        title: "deck.empty.title",
                        message: "deck.empty.message",
                        systemImage: "square.and.pencil"
                    )
                }
                ForEach(notes) { summary in
                    Button {
                        editingNote = summary.note
                    } label: {
                        NoteSummaryLabel(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.row")
                    .swipeActions {
                        Button("common.delete", role: .destructive) {
                            Task {
                                await library.trashNote(summary.note.id)
                                await reload()
                            }
                        }
                        .accessibilityIdentifier("note.delete")
                    }
                }
            }
        }
        .navigationTitle(deck?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("deck.add_note", systemImage: "plus") { isCreating = true }
                    Button("deck.study", systemImage: "play.fill") { studying = true }
                    Button("deck.export", systemImage: "square.and.arrow.up") { isExporting = true }
                } label: {
                    Label("common.more", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("deck.menu")
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorView(library: library, deckID: deckID, note: note) { Task { await reload() } }
        }
        .sheet(isPresented: $isCreating) {
            NoteEditorView(library: library, deckID: deckID, note: nil) { Task { await reload() } }
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(library: library, deckID: deckID, deckName: deck?.name ?? "")
        }
        .fullScreenCover(isPresented: $studying) {
            StudySessionView(library: library, scope: .deck(deckID))
        }
        .onChange(of: filters.state) { Task { await reload() } }
        .task { await reload() }
    }

    private func reload() async {
        deck = await library.deck(deckID)
        notes = await library.notes(in: deckID, filters: filters, now: Date())
    }

    private func stateTitle(_ state: SearchFilters.State) -> LocalizedStringKey {
        switch state {
        case .any: "filter.all"
        case .new: "filter.new"
        case .due: "filter.due"
        case .suspended: "filter.suspended"
        }
    }
}

extension Note: @retroactive Identifiable {}
