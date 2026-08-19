import FlashUpDomain
import Foundation

/// The mutable state behind `InMemoryLibrary`, kept as a plain value type.
///
/// Separating state from the actor keeps every operation a small, testable function over
/// data, and mirrors the shape the Core Data implementation will need: notes and cards are
/// content, schedules and logs are private progress, and the two are joined by `uuid` only
/// (spec §A1.3).
struct LibraryStore: Sendable {
    var decks: [UUID: Deck] = [:]
    var notes: [UUID: Note] = [:]
    /// Soft deletion (spec §A2): trashed content stays recoverable for 30 days.
    var noteDeletedAt: [UUID: Date] = [:]
    var deckDeletedAt: [UUID: Date] = [:]
    var cards: [UUID: Card] = [:]
    var contentHashes: [UUID: String] = [:]

    var schedules: [UUID: ReviewState] = [:]
    var logs: [ReviewLog] = []
    var importBatches: [UUID: ImportBatch] = [:]
    var settings: StudySettings = .default
    var session: SessionState?

    mutating func mergeDemoSeed(_ seed: LibraryStore) {
        for (id, deck) in seed.decks where decks[id] == nil { decks[id] = deck }
        for deck in seed.decks.values where deck.isDemo {
            if var existing = decks[deck.id], existing.demoVersion < deck.demoVersion {
                existing.isDemo = true
                existing.demoSeedID = deck.demoSeedID
                existing.demoVersion = deck.demoVersion
                existing.updatedAt = deck.updatedAt
                decks[deck.id] = existing
            }
        }
        for (id, note) in seed.notes where notes[id] == nil { notes[id] = note }
        for (id, card) in seed.cards where cards[id] == nil { cards[id] = card }
        for (id, state) in seed.schedules where schedules[id] == nil { schedules[id] = state }
        for (id, hash) in seed.contentHashes where contentHashes[id] == nil { contentHashes[id] = hash }
        for (id, date) in seed.noteDeletedAt where noteDeletedAt[id] == nil { noteDeletedAt[id] = date }
        for (id, date) in seed.deckDeletedAt where deckDeletedAt[id] == nil { deckDeletedAt[id] = date }
        for (id, batch) in seed.importBatches where importBatches[id] == nil { importBatches[id] = batch }
        let existingLogs = Set(logs.map(\.id))
        logs.append(contentsOf: seed.logs.filter { !existingLogs.contains($0.id) })
    }

    // MARK: - Derived reads

    var liveDecks: [Deck] {
        decks.values
            .filter { deckDeletedAt[$0.id] == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func liveNotes(in deckID: UUID? = nil) -> [Note] {
        notes.values.filter { note in
            guard noteDeletedAt[note.id] == nil, deckDeletedAt[note.deckID] == nil else { return false }
            return deckID.map { $0 == note.deckID } ?? true
        }
    }

    func cards(forNote noteID: UUID) -> [Card] {
        cards.values.filter { $0.noteID == noteID }.sorted { $0.templateKey < $1.templateKey }
    }

    func liveCards(in scope: StudyScope) -> [Card] {
        cards.values.filter { card in
            guard noteDeletedAt[card.noteID] == nil, deckDeletedAt[card.deckID] == nil else { return false }
            switch scope {
            case .allDecks: return true
            case let .deck(id): return card.deckID == id
            }
        }
    }

    func candidates(in scope: StudyScope) -> [QueueCandidate] {
        liveCards(in: scope).map { card in
            QueueCandidate(
                card: card,
                schedule: schedules[card.id],
                noteCreatedAt: notes[card.noteID]?.createdAt ?? .distantPast
            )
        }
    }

    /// Answers recorded today, split the way the daily limits count them.
    func progress(in scope: StudyScope, now: Date, calendar: Calendar = .current) -> QueueBuilder.DailyProgress {
        let deckID: UUID? = {
            if case let .deck(id) = scope { return id }
            return nil
        }()

        let today = logs.filter { log in
            guard !log.isRevoked, calendar.isDate(log.reviewedAt, inSameDayAs: now) else { return false }
            return deckID.map { $0 == log.deckID } ?? true
        }

        return QueueBuilder.DailyProgress(
            reviewsDoneToday: today.filter { $0.previous.state != .new }.count,
            newIntroducedToday: today.filter { $0.previous.state == .new }.count
        )
    }

    func logs(forCard cardID: UUID) -> [ReviewLog] {
        logs.filter { $0.cardID == cardID }
    }

    // MARK: - Mutations

    /// Creates or updates a note and reconciles its cards (spec §A3.1, §A3.2).
    ///
    /// Cards whose template key survives keep their `uuid`, and therefore their schedule
    /// and history — the contract that lets content be edited without losing progress.
    mutating func save(_ draft: NoteDraft, now: Date) -> Note? {
        guard draft.isValid else { return nil }

        let tags = TagNormalizer.canonicalize(draft.tags)
        let note: Note
        if let id = draft.id, let existing = notes[id] {
            var updated = existing
            updated.type = draft.type
            updated.front = draft.front
            updated.back = draft.back
            updated.tags = tags
            updated.mediaIDs = draft.mediaIDs
            updated.updatedAt = now
            note = updated
        } else {
            note = Note(
                id: draft.id ?? UUID(),
                deckID: draft.deckID,
                type: draft.type,
                front: draft.front,
                back: draft.back,
                tags: tags,
                mediaIDs: draft.mediaIDs,
                createdAt: now,
                updatedAt: now
            )
        }

        notes[note.id] = note
        contentHashes[note.id] = ContentFingerprint.hash(type: note.type, front: note.front, back: note.back)
        reconcileCards(for: note)
        return note
    }

    mutating func reconcileCards(for note: Note) {
        let desired = CardGenerator.generate(note)
        let existing = cards(forNote: note.id)
        let desiredKeys = Set(desired.map(\.templateKey))

        // Cards for template keys that no longer exist are removed along with their
        // progress; their template can never come back with the same identity.
        for card in existing where !desiredKeys.contains(card.templateKey) {
            cards.removeValue(forKey: card.id)
            schedules.removeValue(forKey: card.id)
        }

        for template in desired {
            if let survivor = existing.first(where: { $0.templateKey == template.templateKey }) {
                cards[survivor.id] = Card(
                    id: survivor.id,
                    noteID: note.id,
                    deckID: note.deckID,
                    template: template
                )
            } else {
                let card = Card(noteID: note.id, deckID: note.deckID, template: template)
                cards[card.id] = card
            }
        }
    }

    mutating func record(_ transition: ScheduleTransition, for cardID: UUID, durationMs: Int) {
        guard let card = cards[cardID] else { return }
        schedules[cardID] = transition.updated.carryingUserFlags(from: schedules[cardID])
        logs.append(
            ReviewLog(transition: transition, cardID: cardID, deckID: card.deckID, durationMs: durationMs)
        )
    }

    /// Undo: revoke the last live log, then rebuild the card's schedule from what remains.
    mutating func revokeLastAnswer(in scope: StudyScope, using scheduler: FSRSService, now: Date) {
        let deckID: UUID? = {
            if case let .deck(id) = scope { return id }
            return nil
        }()

        guard let index = logs.lastIndex(where: { log in
            !log.isRevoked && (deckID.map { $0 == log.deckID } ?? true)
        }) else { return }

        logs[index].revokedAt = now
        rebuildSchedule(for: logs[index].cardID, using: scheduler)
    }

    mutating func rebuildSchedule(for cardID: UUID, using scheduler: FSRSService) {
        let flags = schedules[cardID]
        let cardLogs = logs(forCard: cardID)
        // Replay starts from the card's first surviving answer, so a rebuilt schedule
        // matches the one the original sequence produced.
        let firstAnswer = cardLogs.filter { !$0.isRevoked }.map(\.reviewedAt).min() ?? Date()
        let replayed = ScheduleReplayer.replay(
            logs: cardLogs,
            using: scheduler,
            initialDueAt: firstAnswer
        )

        if let state = replayed {
            schedules[cardID] = state.carryingUserFlags(from: flags)
        } else {
            setScheduleWithoutHistory(for: cardID, flags: flags, dueAt: firstAnswer)
        }
    }

    /// Reset: revoke every log and send the card back to new (spec §A6.3). Suspension and
    /// burial are not history, so they survive it.
    mutating func resetCard(_ cardID: UUID, now: Date) {
        for index in logs.indices where logs[index].cardID == cardID {
            logs[index].revokedAt = logs[index].revokedAt ?? now
        }
        setScheduleWithoutHistory(for: cardID, flags: schedules[cardID], dueAt: now)
    }

    /// Drops a card's schedule now that it has no surviving answers — unless the user has
    /// hidden it, in which case a flag-only placeholder has to outlive the history. Losing
    /// the flag here would silently un-suspend a card the moment its last answer was undone.
    private mutating func setScheduleWithoutHistory(for cardID: UUID, flags: ReviewState?, dueAt: Date) {
        guard let flags, flags.carriesUserFlag else {
            schedules.removeValue(forKey: cardID)
            return
        }
        schedules[cardID] = ReviewState.unseen(dueAt: dueAt).carryingUserFlags(from: flags)
    }
}
