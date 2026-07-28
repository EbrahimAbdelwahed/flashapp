import FlashUpDomain
import Foundation

/// Import, export, backup, restore and erasure (spec §A9, §A10).
extension InMemoryLibrary {
    public func commitImport(
        _ plan: ImportPlan,
        into deckID: UUID,
        sourceName: String,
        wasNewDeck: Bool
    ) async -> ImportBatch {
        let now = Date()
        var createdIDs: [UUID] = []

        mutate { store in
            for row in plan.rowsToImport {
                let draft = NoteDraft(
                    deckID: deckID,
                    type: row.type,
                    front: row.front,
                    back: row.back,
                    tags: row.tags
                )
                if let note = store.save(draft, now: now) {
                    createdIDs.append(note.id)
                }
            }
        }

        let batch = ImportBatch(
            sourceName: sourceName,
            importedAt: now,
            destinationDeckID: deckID,
            destinationWasNewDeck: wasNewDeck,
            createdNoteIDs: createdIDs
        )
        mutate { $0.importBatches[batch.id] = batch }
        return batch
    }

    /// Undo sends the imported notes to the trash rather than destroying them: fully
    /// recoverable, and consistent with every other deletion in the app (spec §A9.2).
    public func undoImport(_ batchID: UUID) async {
        let now = Date()
        mutate { store in
            guard var batch = store.importBatches[batchID], batch.undoneAt == nil else { return }
            for noteID in batch.createdNoteIDs {
                store.noteDeletedAt[noteID] = now
            }
            batch.undoneAt = now
            store.importBatches[batchID] = batch
        }
    }

    public func exportCSV(deckID: UUID?) async -> Data {
        let notes = read { store in
            store.liveNotes(in: deckID).sorted { $0.createdAt < $1.createdAt }
        }
        return CSVWriter.data(for: notes)
    }

    public func backupDocument(appVersion: String, now: Date) async -> BackupDocument {
        read { store in
            // Demo and trashed content are excluded (spec §A10).
            let decks = store.liveDecks.filter { !$0.isDemo }
            let deckIDs = Set(decks.map(\.id))

            let backupDecks = decks.map { deck in
                BackupDeck(
                    uuid: deck.id,
                    name: deck.name,
                    origin: deck.groupID == nil ? .personal : .sharedSnapshot,
                    createdAt: deck.createdAt,
                    notes: store.liveNotes(in: deck.id).map { note in
                        BackupNote(
                            uuid: note.id,
                            type: note.type,
                            front: note.front,
                            back: note.back,
                            tags: note.tags,
                            createdAt: note.createdAt,
                            updatedAt: note.updatedAt,
                            cards: store.cards(forNote: note.id).map {
                                BackupCard(uuid: $0.id, templateKey: $0.templateKey)
                            }
                        )
                    }
                )
            }

            let exportedCardIDs = Set(backupDecks.flatMap { $0.notes.flatMap { $0.cards.map(\.uuid) } })

            return BackupDocument(
                appVersion: appVersion,
                exportedAt: now,
                settings: store.settings,
                decks: backupDecks,
                schedules: store.schedules
                    .filter { exportedCardIDs.contains($0.key) }
                    .map { BackupSchedule(cardUUID: $0.key, state: $0.value) },
                reviewLogs: store.logs
                    .filter { deckIDs.contains($0.deckID) }
                    .map(BackupReviewLog.init)
            )
        }
    }

    /// Restores by uuid and never overwrites live data (spec §A10): an existing uuid is
    /// skipped, so a restore can only ever add.
    public func restore(_ document: BackupDocument) async -> RestoreSummary {
        var decksAdded = 0
        var notesAdded = 0
        var notesSkipped = 0
        var logsAdded = 0

        mutate { store in
            for backupDeck in document.decks {
                if store.decks[backupDeck.uuid] == nil {
                    store.decks[backupDeck.uuid] = Deck(
                        id: backupDeck.uuid,
                        name: backupDeck.name,
                        createdAt: backupDeck.createdAt,
                        updatedAt: backupDeck.createdAt,
                        isDemo: false,
                        // A backup never recreates a group: shared snapshots come back
                        // as personal decks.
                        groupID: nil
                    )
                    decksAdded += 1
                }

                for backupNote in backupDeck.notes {
                    guard store.notes[backupNote.uuid] == nil else {
                        notesSkipped += 1
                        continue
                    }
                    let note = Note(
                        id: backupNote.uuid,
                        deckID: backupDeck.uuid,
                        type: backupNote.type,
                        front: backupNote.front,
                        back: backupNote.back,
                        tags: backupNote.tags,
                        createdAt: backupNote.createdAt,
                        updatedAt: backupNote.updatedAt
                    )
                    store.notes[note.id] = note
                    store.contentHashes[note.id] = ContentFingerprint.hash(
                        type: note.type,
                        front: note.front,
                        back: note.back
                    )
                    store.reconcileCards(for: note)
                    notesAdded += 1
                }
            }

            logsAdded = Self.restoreProgress(from: document, into: &store)
        }

        return RestoreSummary(
            decksAdded: decksAdded,
            notesAdded: notesAdded,
            notesSkipped: notesSkipped,
            logsAdded: logsAdded
        )
    }

    /// Schedules restore only when absent and logs merge append-only by uuid, so a restore
    /// can never rewrite history the device already has.
    private static func restoreProgress(from document: BackupDocument, into store: inout LibraryStore) -> Int {
        for schedule in document.schedules where store.schedules[schedule.cardUUID] == nil {
            store.schedules[schedule.cardUUID] = schedule.reviewState
        }

        var added = 0
        let knownLogIDs = Set(store.logs.map(\.id))
        for backupLog in document.reviewLogs where !knownLogIDs.contains(backupLog.uuid) {
            guard let log = backupLog.reviewLog else { continue }
            store.logs.append(log)
            added += 1
        }
        return added
    }

    public func deleteAllData() async {
        mutate { $0 = LibraryStore() }
    }
}
