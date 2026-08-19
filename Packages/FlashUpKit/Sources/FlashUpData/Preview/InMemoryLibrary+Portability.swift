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
                    tags: row.tags,
                    mediaIDs: row.mediaIDs
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
                            },
                            mediaIDs: note.mediaIDs
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
        var restoredCardIDs: [UUID: UUID] = [:]

        mutate { store in
            for backupDeck in document.decks {
                if store.decks[backupDeck.uuid] == nil {
                    store.decks[backupDeck.uuid] = Deck(
                        id: backupDeck.uuid,
                        name: backupDeck.name,
                        createdAt: backupDeck.createdAt,
                        updatedAt: backupDeck.createdAt,
                        isDemo: false
                    )
                    decksAdded += 1
                }

                for backupNote in backupDeck.notes {
                    if Self.restoreNote(backupNote, into: backupDeck.uuid, store: &store) {
                        notesAdded += 1
                    } else {
                        notesSkipped += 1
                    }
                    let restoredCards = store.cards(forNote: backupNote.uuid)
                    for backupCard in backupNote.cards {
                        if let card = restoredCards.first(where: { $0.templateKey == backupCard.templateKey }) {
                            restoredCardIDs[backupCard.uuid] = card.id
                        }
                    }
                }
            }

            logsAdded = Self.restoreProgress(
                from: document,
                cardIDMap: restoredCardIDs,
                into: &store
            )
        }

        return RestoreSummary(
            decksAdded: decksAdded,
            notesAdded: notesAdded,
            notesSkipped: notesSkipped,
            logsAdded: logsAdded
        )
    }

    /// Adds one note, or reports that its uuid was already present. Returns `true` when the
    /// note was created.
    private static func restoreNote(
        _ backupNote: BackupNote,
        into deckID: UUID,
        store: inout LibraryStore
    ) -> Bool {
        guard store.notes[backupNote.uuid] == nil else { return false }

        let note = Note(
            id: backupNote.uuid,
            deckID: deckID,
            type: backupNote.type,
            front: backupNote.front,
            back: backupNote.back,
            tags: backupNote.tags,
            // Attachment ids come back even when their bytes did not: the backup carries
            // references, not blobs, and a missing one renders as a placeholder (ADR-004 §7).
            mediaIDs: backupNote.mediaIDs,
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
        return true
    }

    /// Schedules restore only when absent and logs merge append-only by uuid, so a restore
    /// can never rewrite history the device already has.
    private static func restoreProgress(
        from document: BackupDocument,
        cardIDMap: [UUID: UUID],
        into store: inout LibraryStore
    ) -> Int {
        for schedule in document.schedules {
            guard let cardID = cardIDMap[schedule.cardUUID],
                  store.cards[cardID] != nil,
                  store.schedules[cardID] == nil else { continue }
            store.schedules[cardID] = schedule.reviewState
        }

        var added = 0
        let knownLogIDs = Set(store.logs.map(\.id))
        for backupLog in document.reviewLogs where !knownLogIDs.contains(backupLog.uuid) {
            guard let cardID = cardIDMap[backupLog.cardUUID],
                  store.cards[cardID] != nil,
                  let log = backupLog.reviewLog else { continue }
            store.logs.append(ReviewLog(
                id: log.id,
                cardID: cardID,
                deckID: log.deckID,
                reviewedAt: log.reviewedAt,
                durationMs: log.durationMs,
                grade: log.grade,
                previous: log.previous,
                scheduledDays: log.scheduledDays,
                elapsedDays: log.elapsedDays,
                revokedAt: log.revokedAt
            ))
            added += 1
        }
        return added
    }

    public func deleteAllData() async {
        mutate { $0 = LibraryStore() }
    }
}
