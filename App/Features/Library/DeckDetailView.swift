import FlashUpDomain
import SwiftUI

/// The notes inside one deck, with the filters of spec §A11.5.
struct DeckDetailView: View {
    let library: any LibraryRepository
    let deckID: UUID

    @State private var deck: Deck?
    @State private var summary: DeckSummary?
    @State private var notes: [NoteSummary] = []
    @State private var filters = SearchFilters()
    @State private var editingNote: Note?
    @State private var isCreating = false
    @State private var isExporting = false
    @State private var studying = false

    var body: some View {
        List {
            if let summary {
                Section("deck.schedule") {
                    DeckScheduleRow(
                        title: "deck.schedule.today",
                        count: summary.dueCount + summary.newCount,
                        detail: LocalizedStringKey("deck.schedule.today.detail \(summary.dueCount) \(summary.newCount)")
                    )

                    if summary.tomorrowCount > 0 {
                        DeckScheduleRow(title: "deck.schedule.tomorrow", count: summary.tomorrowCount)
                    }
                    if summary.thisWeekCount > 0 {
                        DeckScheduleRow(title: "deck.schedule.this_week", count: summary.thisWeekCount)
                    }
                    if summary.laterCount > 0 {
                        DeckScheduleRow(title: "deck.schedule.later", count: summary.laterCount)
                    }
                    if summary.suspendedCount > 0 {
                        DeckScheduleRow(title: "deck.schedule.suspended", count: summary.suspendedCount)
                    }
                }
                .paperRows()
                .accessibilityIdentifier("deck.schedule")
            }

            Section {
                // A menu, not segments: five states do not fit across an iPhone, and the
                // two that matter here are the ones a user reaches for rarely and on
                // purpose.
                Picker("filter.state", selection: $filters.state) {
                    ForEach(SearchFilters.State.allCases, id: \.self) { state in
                        Text(stateTitle(state)).tag(state)
                    }
                }
                .accessibilityIdentifier("deck.filter")
            }
            .paperRows()

            Section("deck.notes \(notes.count)") {
                if notes.isEmpty {
                    // An empty filter is not an empty deck: inviting the user to write their
                    // first note when they have simply filtered to Suspended would be a lie.
                    if filters.state == .any {
                        EmptyStateRow(
                            title: "deck.empty.title",
                            message: "deck.empty.message",
                            systemImage: "square.and.pencil"
                        )
                    } else {
                        EmptyStateRow(
                            title: "deck.filter_empty.title",
                            message: "deck.filter_empty.message",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
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
                    // Offered only where there is something to lift, so the gesture never
                    // rewards a swipe with nothing. This is the way out of a suspension:
                    // filter to Suspended, swipe, and the note is back in the queue.
                    .swipeActions(edge: .leading) {
                        if summary.isHidden {
                            Button("note.resume", systemImage: "play.circle") {
                                Task {
                                    await library.resumeNote(summary.note.id)
                                    await reload()
                                }
                            }
                            .tint(Palette.success)
                            .accessibilityIdentifier("note.resume")
                        }
                    }
                }
            }
            .paperRows()
        }
        .screenCanvas()
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
        let summaries = await library.decks()
        summary = summaries.first { $0.deck.id == deckID }
        notes = await library.notes(in: deckID, filters: filters, now: Date())
    }

    private func stateTitle(_ state: SearchFilters.State) -> LocalizedStringKey {
        switch state {
        case .any: "filter.all"
        case .new: "filter.new"
        case .due: "filter.due"
        case .suspended: "filter.suspended"
        case .buried: "filter.buried"
        }
    }
}

private struct DeckScheduleRow: View {
    let title: LocalizedStringKey
    let count: Int
    var detail: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.normal) {
                Text(title)
                    .font(.body.weight(.medium))

                Spacer(minLength: Spacing.tight)

                Text("deck.schedule.count \(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension Note: @retroactive Identifiable {}
