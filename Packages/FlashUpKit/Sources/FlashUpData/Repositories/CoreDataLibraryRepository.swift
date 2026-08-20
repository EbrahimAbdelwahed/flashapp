import CoreData
import CloudKit
import FlashUpDomain
import Foundation

// This adapter intentionally keeps the Core Data projection in one file so the value-level
// contract and its persistence mapping can be reviewed together. The mapping functions are
// split by entity below; the project-wide lint thresholds are not useful for this boundary.
// swiftlint:disable file_length

private enum CoreDataMappingError: Error, Equatable {
    case malformedPersistedData
}

/// The production library backed by the V1 Core Data model.
///
/// `LibraryStore` remains the value-level oracle for the pure domain behavior. Persistence is
/// deliberately different from the preview implementation: a mutation computes a value-level
/// delta, then applies only the changed Core Data rows. A stale snapshot can therefore never
/// turn an unrelated row (or a CloudKit-imported row) into a deletion.
public actor CoreDataLibraryRepository: LibraryRepository { // swiftlint:disable:this type_body_length
    private let persistence: PersistenceController?
    private let scheduler: FSRSService
    private let sessionURL: URL
    private let syncMonitor: SyncMonitor
    private let historyProcessor: RemoteChangeProcessor
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var failure: LibraryRepositoryError?
    private enum Lifecycle {
        case open
        case revoked
        case closed
    }
    private var lifecycle: Lifecycle = .open
    private var closeStarted = false

    public init(
        persistenceController: PersistenceController,
        scheduler: FSRSService = SwiftFSRSAdapter(),
        sessionURL: URL? = nil,
        status: SyncStatus = .accountUnavailable,
        syncMonitor: SyncMonitor? = nil
    ) {
        self.persistence = persistenceController
        self.scheduler = scheduler
        self.sessionURL = sessionURL ?? Self.defaultSessionURL(for: persistenceController)
        let monitor = syncMonitor ?? Self.monitor(for: status)
        let processor = Self.historyProcessor(for: persistenceController, scheduler: scheduler)
        self.syncMonitor = monitor
        self.historyProcessor = processor
        self.remoteChangeObserver = Self.observeRemoteChanges(
            for: persistenceController,
            processor: processor,
            monitor: monitor
        )
        self.cloudKitEventObserver = Self.observeCloudKitEvents(
            for: persistenceController.container,
            monitor: monitor
        )
        self.failure = nil
    }

    public init(
        configuration: PersistenceConfiguration,
        scheduler: FSRSService = SwiftFSRSAdapter(),
        sessionURL: URL? = nil,
        status: SyncStatus = .accountUnavailable,
        syncMonitor: SyncMonitor? = nil
    ) throws {
        let persistence = try PersistenceController(configuration: configuration)
        self.init(
            persistenceController: persistence,
            scheduler: scheduler,
            sessionURL: sessionURL,
            status: status,
            syncMonitor: syncMonitor
        )
    }

    private init(unavailable error: LibraryRepositoryError, scheduler: FSRSService = SwiftFSRSAdapter()) {
        self.persistence = nil
        self.scheduler = scheduler
        self.sessionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashApp-unavailable-session.json")
        self.syncMonitor = SyncMonitor(initialAccountState: .couldNotDetermine)
        self.historyProcessor = RemoteChangeProcessor(
            tokenURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("FlashApp-unavailable-history.token"),
            fetchHistory: { _ in [] },
            replay: { _ in }
        )
        self.remoteChangeObserver = nil
        self.cloudKitEventObserver = nil
        self.failure = error
    }

    deinit {
        let center = NotificationCenter.default
        if let remoteChangeObserver { center.removeObserver(remoteChangeObserver) }
        if let cloudKitEventObserver { center.removeObserver(cloudKitEventObserver) }
    }

    public static func unavailable(_ error: LibraryRepositoryError) -> CoreDataLibraryRepository {
        CoreDataLibraryRepository(unavailable: error)
    }

    /// The shipping composition uses the CloudKit-capable container and a device-local
    /// session file. Account, entitlement and production-schema verification remain human
    /// release gates; this initializer never substitutes an in-memory repository.
    public static func production(
        containerIdentifier: String = "iCloud.com.flashup.app",
        fileManager: FileManager = .default
    ) throws -> CoreDataLibraryRepository {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("FlashApp", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Private.sqlite")
        let sessionURL = directory.appendingPathComponent("session-state.json")
        let configuration = PersistenceConfiguration.cloudKit(
            storeURL: storeURL,
            containerIdentifier: containerIdentifier
        )
        return try CoreDataLibraryRepository(
            configuration: configuration,
            sessionURL: sessionURL,
            status: .accountUnavailable,
            syncMonitor: .cloudKit(containerIdentifier: containerIdentifier)
        )
    }

    public func repositoryState() async -> LibraryRepositoryState {
        guard lifecycle == .open else { return .failed(.persistenceUnavailable) }
        return failure.map(LibraryRepositoryState.failed) ?? .ready
    }

    /// Quiesces the owned coordinator before a composition root replaces this repository.
    /// A retry must never leave two live SQLite/CloudKit owners attached to the same URL.
    public func close() async throws {
        guard !closeStarted else { return }
        closeStarted = true
        lifecycle = .revoked
        failure = .persistenceUnavailable
        persistence?.beginWriteFence()
        removeObservers()
        await historyProcessor.close()
        guard let persistence else { return }
        do {
            try persistence.close()
            lifecycle = .closed
        } catch {
            throw LibraryRepositoryError.writeFailed
        }
    }

    /// Fences the owned persistence controller before an account transition starts. The
    /// coordinator then calls `close()` to drain and unload this owner.
    public func beginAccountTransition() {
        guard lifecycle == .open else { return }
        lifecycle = .revoked
        failure = .persistenceUnavailable
        persistence?.beginWriteFence()
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let remoteChangeObserver {
            center.removeObserver(remoteChangeObserver)
            self.remoteChangeObserver = nil
        }
        if let cloudKitEventObserver {
            center.removeObserver(cloudKitEventObserver)
            self.cloudKitEventObserver = nil
        }
    }

    // MARK: Reading

    public func todaySnapshot(now: Date) async throws -> TodaySnapshot {
        try read { store in
            let candidates = store.candidates(in: .allDecks)
            return TodaySnapshot(
                dueCount: QueueBuilder.dueCount(candidates: candidates, now: now),
                newCount: QueueBuilder.newCount(candidates: candidates, now: now),
                metrics: MetricsCalculator.metrics(logs: store.logs, now: now),
                decks: Self.deckSummaries(store: store, now: now)
            )
        }
    }

    public func metrics(now: Date) async throws -> StudyMetrics {
        try read { MetricsCalculator.metrics(logs: $0.logs, now: now) }
    }

    public func decks() async throws -> [DeckSummary] {
        try read { Self.deckSummaries(store: $0, now: Date()) }
    }

    public func deck(_ id: UUID) async throws -> Deck? {
        try read { $0.deckDeletedAt[id] == nil ? $0.decks[id] : nil }
    }

    public func notes(in deckID: UUID, filters: SearchFilters, now: Date) async throws -> [NoteSummary] {
        try read { Self.summaries(store: $0, notes: $0.liveNotes(in: deckID), filters: filters, now: now) }
    }

    public func search(_ filters: SearchFilters, now: Date) async throws -> [NoteSummary] {
        try read { Self.summaries(store: $0, notes: $0.liveNotes(), filters: filters, now: now) }
    }

    public func note(_ id: UUID) async throws -> Note? {
        try read { $0.noteDeletedAt[id] == nil ? $0.notes[id] : nil }
    }

    public func cards(for noteID: UUID) async throws -> [Card] {
        try read { $0.cards(forNote: noteID) }
    }

    public func trashedNotes() async throws -> [Note] {
        try read { store in
            store.noteDeletedAt.keys.compactMap { store.notes[$0] }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func contentHashes(in deckID: UUID) async throws -> [UUID: String] {
        try read { store in
            var hashes: [UUID: String] = [:]
            for note in store.liveNotes(in: deckID) {
                if let hash = store.contentHashes[note.id] { hashes[note.id] = hash }
            }
            return hashes
        }
    }

    public func settings() async throws -> StudySettings {
        try read { $0.settings }
    }

    public func syncStatus() async throws -> SyncStatus {
        guard lifecycle == .open else { throw LibraryRepositoryError.persistenceUnavailable }
        guard persistence != nil else {
            failure = .persistenceUnavailable
            throw LibraryRepositoryError.persistenceUnavailable
        }
        if let failure { throw failure }
        return await syncMonitor.snapshot().status
    }

    public func retrySync() async throws {
        guard lifecycle == .open else { throw LibraryRepositoryError.persistenceUnavailable }
        guard let persistence else {
            failure = .persistenceUnavailable
            throw LibraryRepositoryError.persistenceUnavailable
        }
        if let failure { throw failure }

        let snapshot = await syncMonitor.refreshAccountStatus()
        guard snapshot.accountState == .available else {
            // No account, restricted, temporarily unavailable and indeterminate states are
            // truthful availability outcomes, not successful syncs and not repository errors.
            return
        }

        do {
            _ = await syncMonitor.markSyncing()
            try persistence.save()
            _ = try await historyProcessor.processNow()
        } catch {
            _ = await syncMonitor.markFailed(reason: "iCloud sync could not be refreshed.")
            throw LibraryRepositoryError.writeFailed
        }
    }

    /// Processes already-imported persistent history without replacing the local store.
    @discardableResult
    public func refreshRemoteChanges() async throws -> RemoteProcessingResult {
        guard lifecycle == .open else { throw LibraryRepositoryError.persistenceUnavailable }
        do {
            let result = try await historyProcessor.processNow()
            return result
        } catch let error as RemoteChangeProcessorError {
            throw error
        } catch {
            throw LibraryRepositoryError.readFailed
        }
    }

    /// Debounces Core Data remote-change notifications into one history pass.
    public func notifyRemoteChange() async {
        guard lifecycle == .open else { return }
        await historyProcessor.notifyRemoteChange()
    }

    // MARK: Studying

    public func studyQueue(scope: StudyScope, now: Date) async throws -> [Card] {
        try read { store in
            QueueBuilder.build(
                candidates: store.candidates(in: scope),
                settings: store.settings,
                progress: store.progress(in: scope, now: now),
                now: now
            )
        }
    }

    public func cards(withIDs ids: [UUID]) async throws -> [Card] {
        try read { store in ids.compactMap { store.cards[$0] } }
    }

    public func schedule(for cardID: UUID) async throws -> ReviewState? {
        try read { $0.schedules[cardID] }
    }

    public func record(_ transition: ScheduleTransition, for cardID: UUID, durationMs: Int) async throws {
        try mutate { store in store.record(transition, for: cardID, durationMs: durationMs) }
    }

    public func revokeLastAnswer(in scope: StudyScope) async throws {
        try mutate { store in store.revokeLastAnswer(in: scope, using: scheduler, now: Date()) }
    }

    public func setSuspended(_ suspended: Bool, cardIDs: [UUID]) async throws {
        let now = Date()
        try mutate { store in
            for cardID in cardIDs {
                var state = store.schedules[cardID] ?? .unseen(dueAt: now)
                state.suspendedAt = suspended ? now : nil
                if !state.carriesUserFlag, state.isUnseen {
                    store.schedules.removeValue(forKey: cardID)
                } else {
                    store.schedules[cardID] = state
                }
            }
        }
    }

    public func setBuried(_ buried: Bool, cardIDs: [UUID], until: Date) async throws {
        let now = Date()
        try mutate { store in
            for cardID in cardIDs {
                var state = store.schedules[cardID] ?? .unseen(dueAt: now)
                state.buriedUntil = buried ? until : nil
                if !state.carriesUserFlag, state.isUnseen {
                    store.schedules.removeValue(forKey: cardID)
                } else {
                    store.schedules[cardID] = state
                }
            }
        }
    }

    public func resumeNote(_ noteID: UUID) async throws {
        let now = Date()
        try mutate { store in
            for card in store.cards(forNote: noteID) {
                var state = store.schedules[card.id] ?? .unseen(dueAt: now)
                state.suspendedAt = nil
                state.buriedUntil = nil
                if state.isUnseen { store.schedules.removeValue(forKey: card.id) } else { store.schedules[card.id] = state }
            }
        }
    }

    public func resetCard(_ cardID: UUID) async throws {
        try mutate { $0.resetCard(cardID, now: Date()) }
    }

    public func cardInfo(_ cardID: UUID) async throws -> CardInfo? {
        try read { store in
            guard let card = store.cards[cardID] else { return nil }
            return CardInfo(
                card: card,
                schedule: store.schedules[cardID],
                logs: store.logs(forCard: cardID).filter { !$0.isRevoked }.sorted { $0.reviewedAt > $1.reviewedAt }
            )
        }
    }

    public func storedSession() async throws -> SessionState? {
        guard lifecycle == .open else { throw LibraryRepositoryError.sessionFailed }
        let data: Data
        do {
            data = try Data(contentsOf: sessionURL)
        } catch {
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                failure = .sessionFailed
                throw LibraryRepositoryError.sessionFailed
            }
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let state = try decoder.decode(SessionState.self, from: data)
            failure = nil
            return state
        } catch {
            failure = .sessionFailed
            throw LibraryRepositoryError.sessionFailed
        }
    }

    public func storeSession(_ state: SessionState?) async throws {
        guard lifecycle == .open else { throw LibraryRepositoryError.sessionFailed }
        guard let state else {
            do {
                try FileManager.default.removeItem(at: sessionURL)
                failure = nil
            } catch {
                if FileManager.default.fileExists(atPath: sessionURL.path) {
                    failure = .sessionFailed
                    throw LibraryRepositoryError.sessionFailed
                }
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else {
            failure = .sessionFailed
            throw LibraryRepositoryError.sessionFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: sessionURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: sessionURL, options: .atomic)
            failure = nil
        } catch {
            failure = .sessionFailed
            throw LibraryRepositoryError.sessionFailed
        }
    }

    // MARK: Writing

    public func createDeck(named name: String) async throws -> Deck {
        try mutate { store in
            let deck = Deck(name: name)
            store.decks[deck.id] = deck
            return deck
        }
    }

    public func renameDeck(_ deckID: UUID, to name: String) async throws {
        try mutate { store in
            guard var deck = store.decks[deckID] else { return }
            deck.name = name
            deck.updatedAt = Date()
            store.decks[deckID] = deck
        }
    }

    public func trashDeck(_ deckID: UUID) async throws {
        try mutate { $0.deckDeletedAt[deckID] = Date() }
    }

    @discardableResult
    public func saveNote(_ draft: NoteDraft) async throws -> Note? {
        try mutate { $0.save(draft, now: Date()) }
    }

    public func trashNote(_ noteID: UUID) async throws {
        try mutate { $0.noteDeletedAt[noteID] = Date() }
    }

    public func restoreNote(_ noteID: UUID) async throws {
        _ = try mutate { $0.noteDeletedAt.removeValue(forKey: noteID) }
    }

    public func emptyTrash() async throws {
        try mutate { store in
            for noteID in store.noteDeletedAt.keys {
                for card in store.cards(forNote: noteID) {
                    store.cards.removeValue(forKey: card.id)
                    store.schedules.removeValue(forKey: card.id)
                    store.logs.removeAll { $0.cardID == card.id }
                }
                store.notes.removeValue(forKey: noteID)
                store.contentHashes.removeValue(forKey: noteID)
            }
            store.noteDeletedAt.removeAll()
            for deckID in store.deckDeletedAt.keys {
                let noteIDs = store.notes.values.filter { $0.deckID == deckID }.map(\.id)
                for noteID in noteIDs {
                    for card in store.cards(forNote: noteID) {
                        store.cards.removeValue(forKey: card.id)
                        store.schedules.removeValue(forKey: card.id)
                        store.logs.removeAll { $0.cardID == card.id }
                    }
                    store.notes.removeValue(forKey: noteID)
                    store.noteDeletedAt.removeValue(forKey: noteID)
                    store.contentHashes.removeValue(forKey: noteID)
                }
                store.decks.removeValue(forKey: deckID)
            }
            store.deckDeletedAt.removeAll()
        }
    }

    public func updateSettings(_ settings: StudySettings) async throws {
        try mutate { $0.settings = settings }
    }

    public func installDemoDeck() async throws {
        try mutate { store in
            let existingVersion = store.decks.values
                .first(where: { $0.isDemo })?
                .demoVersion ?? 0
            guard existingVersion < DemoContent.version else { return }
            store.mergeDemoSeed(DemoContent.seededStore(scheduler: scheduler))
        }
    }

    // MARK: Portability

    public func commitImport(
        _ plan: ImportPlan,
        into deckID: UUID,
        sourceName: String,
        wasNewDeck: Bool
    ) async throws -> ImportBatch {
        let now = Date()
        return try mutate { store in
            var createdIDs: [UUID] = []
            for row in plan.rowsToImport {
                let draft = NoteDraft(
                    deckID: deckID,
                    type: row.type,
                    front: row.front,
                    back: row.back,
                    tags: row.tags,
                    mediaIDs: row.mediaIDs
                )
                if let note = store.save(draft, now: now) { createdIDs.append(note.id) }
            }
            let batch = ImportBatch(
                sourceName: sourceName,
                importedAt: now,
                destinationDeckID: deckID,
                destinationWasNewDeck: wasNewDeck,
                createdNoteIDs: createdIDs
            )
            store.importBatches[batch.id] = batch
            return batch
        }
    }

    public func undoImport(_ batchID: UUID) async throws {
        let now = Date()
        try mutate { store in
            guard var batch = store.importBatches[batchID], batch.undoneAt == nil else { return }
            for noteID in batch.createdNoteIDs { store.noteDeletedAt[noteID] = now }
            batch.undoneAt = now
            store.importBatches[batchID] = batch
        }
    }

    public func exportCSV(deckID: UUID?) async throws -> Data {
        try read { CSVWriter.data(for: $0.liveNotes(in: deckID).sorted { $0.createdAt < $1.createdAt }) }
    }

    public func backupDocument(appVersion: String, now: Date) async throws -> BackupDocument {
        try read {
            Self.backup(from: $0, appVersion: appVersion, now: now)
        }
    }

    public func restore(_ document: BackupDocument) async throws -> RestoreSummary {
        try mutate { store in
            var decksAdded = 0
            var notesAdded = 0
            var notesSkipped = 0
            var restoredCardIDs: [UUID: UUID] = [:]
            for backupDeck in document.decks {
                if store.decks[backupDeck.uuid] == nil {
                    store.decks[backupDeck.uuid] = Deck(
                        id: backupDeck.uuid,
                        name: backupDeck.name,
                        createdAt: backupDeck.createdAt,
                        updatedAt: backupDeck.createdAt
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
            let logsAdded = Self.restoreProgress(
                from: document,
                cardIDMap: restoredCardIDs,
                into: &store
            )
            return RestoreSummary(
                decksAdded: decksAdded,
                notesAdded: notesAdded,
                notesSkipped: notesSkipped,
                logsAdded: logsAdded
            )
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func deleteAllData() async throws {
        guard let persistence else {
            failure = .persistenceUnavailable
            throw LibraryRepositoryError.persistenceUnavailable
        }
        do {
            try persistence.performBackgroundTask { context in
                for object in try context.fetch(CDReviewLog.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDSchedule.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDCard.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDNote.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDDeck.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDTag.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDImportBatch.fetchRequest()) { context.delete(object) }
                for object in try context.fetch(CDStudySettings.fetchRequest()) { context.delete(object) }
            }
            failure = nil
        } catch {
            failure = .writeFailed
            throw LibraryRepositoryError.writeFailed
        }
        try await storeSession(nil)
        do {
            try persistence.discardRecoveryArtifact()
        } catch {
            failure = .writeFailed
            throw LibraryRepositoryError.writeFailed
        }
    }
}

private extension CoreDataLibraryRepository {
    static var emptyMetrics: StudyMetrics { MetricsCalculator.metrics(logs: [], now: Date()) }

    static func historyProcessor(
        for persistence: PersistenceController,
        scheduler: FSRSService
    ) -> RemoteChangeProcessor {
        RemoteChangeProcessor(
            tokenURL: persistence.historyTokenURL,
            fetchHistory: { tokenData in
                try persistence.fetchPersistentHistory(after: tokenData)
            },
            replay: { transactions in
                try persistence.reconcileRemoteHistory(transactions, using: scheduler)
            },
            replaySchedule: { _ in
                // Schedule replay is applied transactionally by `reconcileRemoteHistory` above.
                // Keep this hook for the processor contract and for deterministic fixture
                // instrumentation; it receives metadata only and never card content.
            },
            postReplay: {
                // Checkpoint the token first; only then is it safe to prune older history.
                try persistence.deletePersistentHistory(olderThan: Date().addingTimeInterval(-7 * 86_400))
            }
        )
    }

    static func observeRemoteChanges(
        for persistence: PersistenceController,
        processor: RemoteChangeProcessor,
        monitor: SyncMonitor
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { _ in
            Task {
                _ = await monitor.markSyncing()
                await processor.notifyRemoteChange()
            }
        }
    }

    static func monitor(for status: SyncStatus) -> SyncMonitor {
        switch status {
        case let .upToDate(lastSyncedAt):
            return SyncMonitor(initialAccountState: .available, lastSyncedAt: lastSyncedAt)
        case .syncing:
            return SyncMonitor(initialAccountState: .available)
        case .offline:
            return SyncMonitor(initialAccountState: .temporarilyUnavailable)
        case .accountUnavailable:
            return SyncMonitor(initialAccountState: .noAccount)
        case .failed:
            return SyncMonitor(initialAccountState: .couldNotDetermine)
        }
    }

    static func defaultSessionURL(for persistence: PersistenceController) -> URL {
        if let storeURL = persistence.configuration.storeURL {
            return storeURL.deletingLastPathComponent().appendingPathComponent("session-state.json")
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashApp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("session-state.json")
    }

    func read<T>(_ body: (LibraryStore) -> T) throws -> T {
        guard lifecycle == .open else { throw LibraryRepositoryError.readFailed }
        guard let persistence else {
            failure = .persistenceUnavailable
            throw LibraryRepositoryError.persistenceUnavailable
        }
        do {
            let value = try persistence.performBackgroundTask { context in
                body(try Self.loadStore(from: context))
            }
            failure = nil
            return value
        } catch let error as LibraryRepositoryError {
            failure = error
            throw error
        } catch {
            let mapped = error is CoreDataMappingError
                ? LibraryRepositoryError.malformedPersistedData
                : LibraryRepositoryError.readFailed
            failure = mapped
            throw mapped
        }
    }

    func mutate<T>(_ body: (inout LibraryStore) -> T, attempt: Int = 0) throws -> T {
        guard lifecycle == .open else { throw LibraryRepositoryError.writeFailed }
        guard let persistence else {
            failure = .persistenceUnavailable
            throw LibraryRepositoryError.persistenceUnavailable
        }
        do {
            let value = try persistence.performBackgroundTask { context in
                let original = try Self.loadStore(from: context)
                var store = original
                let value = body(&store)
                try Self.applyDelta(from: original, to: store, in: context)
                return value
            }
            failure = nil
            return value
        } catch let error as LibraryRepositoryError {
            failure = error
            throw error
        } catch let error as CoreDataMappingError {
            let mapped = error == .malformedPersistedData
                ? LibraryRepositoryError.malformedPersistedData
                : LibraryRepositoryError.writeFailed
            failure = mapped
            throw mapped
        } catch {
            if Self.isMergeConflict(error), attempt < 2 {
                return try mutate(body, attempt: attempt + 1)
            }
            let mapped = LibraryRepositoryError.writeFailed
            failure = mapped
            throw mapped
        }
    }

    private static func isMergeConflict(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else { return false }
        return [NSManagedObjectMergeError, NSManagedObjectConstraintMergeError].contains(nsError.code)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func loadStore(from context: NSManagedObjectContext) throws -> LibraryStore {
        var store = LibraryStore()
        let decks = try context.fetch(CDDeck.fetchRequest())
        let deckByID = try deterministicMap(
            decks,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.name)|\($0.createdAt?.timeIntervalSinceReferenceDate ?? .nan)|\($0.isDemo)" }
        )

        for deck in deckByID.values {
            guard let id = deck.uuid,
                  let createdAt = deck.createdAt,
                  let updatedAt = deck.updatedAt else {
                throw CoreDataMappingError.malformedPersistedData
            }
            store.decks[id] = Deck(
                id: id,
                name: deck.name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDemo: deck.isDemo,
                demoSeedID: deck.demoSeedID,
                demoVersion: Int(deck.demoVersion)
            )
            if let deletedAt = deck.deletedAt { store.deckDeletedAt[id] = deletedAt }
        }

        let notes = try context.fetch(CDNote.fetchRequest())
        let noteByID = try deterministicMap(
            notes,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.deck?.uuid?.uuidString ?? "")|\($0.type)|\($0.front)|\($0.back)" }
        )
        for note in noteByID.values {
            guard let id = note.uuid,
                  let deckID = note.deck?.uuid,
                  deckByID[deckID] != nil,
                  let type = NoteType(rawValue: note.type),
                  let createdAt = note.createdAt,
                  let updatedAt = note.updatedAt,
                  !note.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoreDataMappingError.malformedPersistedData
            }
            let tags = try decodeStrings(note.tagsJSON)
            let mediaIDs = try decodeUUIDs(note.mediaIDsJSON)
            store.notes[id] = Note(
                id: id,
                deckID: deckID,
                type: type,
                front: note.front,
                back: note.back.isEmpty ? nil : note.back,
                tags: TagNormalizer.canonicalize(tags),
                mediaIDs: mediaIDs,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            store.contentHashes[id] = note.contentHash
            if let deletedAt = note.deletedAt { store.noteDeletedAt[id] = deletedAt }
        }

        let cards = try context.fetch(CDCard.fetchRequest())
        let cardByID = try deterministicMap(
            cards,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.note?.uuid?.uuidString ?? "")|\($0.templateKey)" }
        )
        for card in cardByID.values {
            guard let id = card.uuid,
                  let noteID = card.note?.uuid,
                  let note = store.notes[noteID],
                  card.createdAt != nil,
                  card.templateKey.isEmpty == false,
                  let template = CardGenerator.generate(note)
                    .first(where: { $0.templateKey == card.templateKey }) else {
                throw CoreDataMappingError.malformedPersistedData
            }
            store.cards[id] = Card(id: id, noteID: noteID, deckID: note.deckID, template: template)
        }

        let schedules = try context.fetch(CDSchedule.fetchRequest())
        let scheduleByCardID = try deterministicMap(
            schedules,
            id: \.cardUUID,
            updatedAt: \.updatedAt,
            tie: { "\($0.uuid?.uuidString ?? "")|\($0.stateRaw)|\($0.dueAt?.timeIntervalSinceReferenceDate ?? .nan)" }
        )
        for schedule in scheduleByCardID.values {
            guard let cardID = schedule.cardUUID,
                  schedule.uuid != nil,
                  store.cards[cardID] != nil,
                  let state = ScheduleState(rawValue: schedule.stateRaw),
                  let dueAt = schedule.dueAt,
                  schedule.createdAt != nil else {
                throw CoreDataMappingError.malformedPersistedData
            }
            store.schedules[cardID] = ReviewState(
                state: state,
                stability: schedule.stability,
                difficulty: schedule.difficulty,
                dueAt: dueAt,
                lastReviewedAt: schedule.lastReviewedAt,
                reps: Int(schedule.reps),
                lapses: Int(schedule.lapses),
                suspendedAt: schedule.suspendedAt,
                buriedUntil: schedule.buriedUntil
            )
        }

        let logs = try context.fetch(CDReviewLog.fetchRequest())
        let logByID = try deterministicMap(
            logs,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: {
                let date = $0.reviewedAt?.timeIntervalSinceReferenceDate ?? .nan
                let cardID = $0.cardUUID?.uuidString ?? ""
                return "\(date)|\(cardID)|\($0.gradeRaw)"
            }
        )
        for log in logByID.values {
            guard let id = log.uuid,
                  let cardID = log.cardUUID,
                  let deckID = log.deckUUID,
                  store.cards[cardID] != nil,
                  store.decks[deckID] != nil,
                  let reviewedAt = log.reviewedAt,
                  log.createdAt != nil,
                  let grade = Grade(rawValue: log.gradeRaw),
                  let state = ScheduleState(rawValue: log.prevStateRaw),
                  let previousDueAt = log.prevDueAt else {
                throw CoreDataMappingError.malformedPersistedData
            }
            store.logs.append(ReviewLog(
                id: id,
                cardID: cardID,
                deckID: deckID,
                reviewedAt: reviewedAt,
                durationMs: Int(log.durationMs),
                grade: grade,
                previous: ReviewState(
                    state: state,
                    stability: log.prevStability,
                    difficulty: log.prevDifficulty,
                    dueAt: previousDueAt,
                    lastReviewedAt: log.prevLastReviewedAt,
                    reps: Int(log.prevReps),
                    lapses: Int(log.prevLapses)
                ),
                scheduledDays: Int(log.scheduledDays),
                elapsedDays: Int(log.elapsedDays),
                revokedAt: log.revokedAt
            ))
        }

        let batches = try context.fetch(CDImportBatch.fetchRequest())
        let batchByID = try deterministicMap(
            batches,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.importedAt?.timeIntervalSinceReferenceDate ?? .nan)|\($0.sourceName)" }
        )
        for batch in batchByID.values {
            guard let id = batch.uuid,
                  let destination = batch.destinationDeckUUID,
                  store.decks[destination] != nil,
                  let importedAt = batch.importedAt,
                  batch.createdAt != nil else {
                throw CoreDataMappingError.malformedPersistedData
            }
            store.importBatches[id] = ImportBatch(
                id: id,
                sourceName: batch.sourceName,
                importedAt: importedAt,
                destinationDeckID: destination,
                destinationWasNewDeck: batch.destinationWasNewDeck,
                createdNoteIDs: try decodeUUIDs(batch.createdNoteUUIDsJSON),
                undoneAt: batch.undoneAt
            )
        }

        let tags = try context.fetch(CDTag.fetchRequest())
        let tagsByID = try deterministicMap(
            tags,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.normalizedName)|\($0.name)" }
        )
        for tag in tagsByID.values where tag.name.isEmpty || tag.normalizedName.isEmpty {
            throw CoreDataMappingError.malformedPersistedData
        }

        let settingsRows = try context.fetch(CDStudySettings.fetchRequest())
        let settingsByID = try deterministicMap(
            settingsRows,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.singletonKey)|\($0.appearanceRaw)" }
        )
        guard settingsByID.values.allSatisfy({ $0.singletonKey == "primary" }) else {
            throw CoreDataMappingError.malformedPersistedData
        }
        let settings = settingsByID.values.sorted {
            let lhs = $0.updatedAt ?? .distantPast
            let rhs = $1.updatedAt ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return ($0.uuid?.uuidString ?? "") > ($1.uuid?.uuidString ?? "")
        }
        if let settings = settings.first,
           let appearance = StudySettings.Appearance(rawValue: settings.appearanceRaw),
           settings.createdAt != nil {
            store.settings = StudySettings(
                newPerDay: Int(settings.newPerDay),
                reviewsPerDay: Int(settings.reviewsPerDay),
                appearance: appearance,
                reminder: .init(
                    isEnabled: settings.reminderEnabled,
                    hour: Int(settings.reminderHour),
                    minute: Int(settings.reminderMinute)
                )
            )
        } else if settings.isEmpty == false {
            throw CoreDataMappingError.malformedPersistedData
        }
        return store
    }

    // This is intentionally a delta applier, not a database reconciliation. It never
    // interprets a row absent from a value snapshot as deleted unless that row was present in
    // the snapshot immediately before this operation and the operation explicitly removed it.
    // That distinction is what keeps concurrent CloudKit imports and stale repository actors
    // from clobbering each other's writes.
    private static func insert<T: NSManagedObject>(
        _ type: T.Type,
        entityName: String,
        in context: NSManagedObjectContext
    ) throws -> T {
        _ = type
        guard let object = NSEntityDescription.insertNewObject(
            forEntityName: entityName,
            into: context
        ) as? T else {
            throw CoreDataMappingError.malformedPersistedData
        }
        return object
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func applyDelta(
        from before: LibraryStore,
        to store: LibraryStore,
        in context: NSManagedObjectContext
    ) throws {
        let encoder = JSONEncoder()
        let decks = try context.fetch(CDDeck.fetchRequest())
        var deckByID = try deterministicMap(
            decks,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.name)|\($0.createdAt?.timeIntervalSinceReferenceDate ?? .nan)|\($0.isDemo)" }
        )
        let deckIDs = Set(before.decks.keys).union(store.decks.keys).filter {
            before.decks[$0] != store.decks[$0] || before.deckDeletedAt[$0] != store.deckDeletedAt[$0]
        }
        for id in deckIDs {
            if let deck = store.decks[id] {
                let object = try (deckByID[id] ?? Self.insert(CDDeck.self, entityName: "CDDeck", in: context))
                deckByID[id] = object
                object.uuid = id
                object.name = deck.name
                object.createdAt = deck.createdAt
                object.updatedAt = deck.updatedAt
                object.isDemo = deck.isDemo
                object.demoSeedID = deck.demoSeedID
                object.demoVersion = Int16(deck.demoVersion)
                object.deletedAt = store.deckDeletedAt[id]
            } else {
                for object in decks where object.uuid == id { context.delete(object) }
            }
        }

        let notes = try context.fetch(CDNote.fetchRequest())
        var noteByID = try deterministicMap(
            notes,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.deck?.uuid?.uuidString ?? "")|\($0.type)|\($0.front)|\($0.back)" }
        )
        let noteIDs = Set(before.notes.keys).union(store.notes.keys).filter {
            before.notes[$0] != store.notes[$0]
                || before.contentHashes[$0] != store.contentHashes[$0]
                || before.noteDeletedAt[$0] != store.noteDeletedAt[$0]
        }
        for id in noteIDs {
            if let note = store.notes[id], let deck = deckByID[note.deckID] {
                let object = try (noteByID[id] ?? Self.insert(CDNote.self, entityName: "CDNote", in: context))
                noteByID[id] = object
                object.uuid = id
                object.deck = deck
                object.type = note.type.rawValue
                object.front = note.front
                object.back = note.back ?? ""
                object.tagsJSON = String(data: try encoder.encode(note.tags), encoding: .utf8) ?? "[]"
                object.mediaIDsJSON = String(data: try encoder.encode(note.mediaIDs), encoding: .utf8) ?? "[]"
                object.contentHash = store.contentHashes[id] ?? ContentFingerprint.hash(
                    type: note.type,
                    front: note.front,
                    back: note.back
                )
                object.createdAt = note.createdAt
                object.updatedAt = note.updatedAt
                object.deletedAt = store.noteDeletedAt[id]
                try applyTags(note.tags, to: object, context: context)
            } else {
                for object in notes where object.uuid == id { context.delete(object) }
            }
        }

        let cards = try context.fetch(CDCard.fetchRequest())
        let cardByID = try deterministicMap(
            cards,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.note?.uuid?.uuidString ?? "")|\($0.templateKey)" }
        )
        let cardIDs = Set(before.cards.keys).union(store.cards.keys)
            .filter { before.cards[$0] != store.cards[$0] }
        for id in cardIDs {
            if let card = store.cards[id], let note = noteByID[card.noteID] {
                let object = try (cardByID[id] ?? Self.insert(CDCard.self, entityName: "CDCard", in: context))
                object.uuid = id
                object.note = note
                object.templateKey = card.templateKey
                object.deletedAt = nil
            } else {
                for object in cards where object.uuid == id { context.delete(object) }
            }
        }

        let schedules = try context.fetch(CDSchedule.fetchRequest())
        let scheduleByCard = try deterministicMap(
            schedules,
            id: \.cardUUID,
            updatedAt: \.updatedAt,
            tie: { "\($0.uuid?.uuidString ?? "")|\($0.stateRaw)|\($0.dueAt?.timeIntervalSinceReferenceDate ?? .nan)" }
        )
        let scheduleIDs = Set(before.schedules.keys).union(store.schedules.keys).filter {
            before.schedules[$0] != store.schedules[$0]
        }
        for id in scheduleIDs {
            if let state = store.schedules[id] {
                let object = try (
                    scheduleByCard[id] ?? Self.insert(CDSchedule.self, entityName: "CDSchedule", in: context)
                )
                object.uuid = object.uuid ?? id
                object.cardUUID = id
                object.deckUUID = store.cards[id]?.deckID
                object.stateRaw = state.state.rawValue
                object.stability = state.stability
                object.difficulty = state.difficulty
                object.dueAt = state.dueAt
                object.lastReviewedAt = state.lastReviewedAt
                object.reps = Int32(state.reps)
                object.lapses = Int32(state.lapses)
                object.suspendedAt = state.suspendedAt
                object.buriedUntil = state.buriedUntil
            } else {
                for object in schedules where object.cardUUID == id { context.delete(object) }
            }
        }

        let logs = try context.fetch(CDReviewLog.fetchRequest())
        let logByID = try deterministicMap(
            logs,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: {
                let date = $0.reviewedAt?.timeIntervalSinceReferenceDate ?? .nan
                let cardID = $0.cardUUID?.uuidString ?? ""
                return "\(date)|\(cardID)|\($0.gradeRaw)"
            }
        )
        let beforeLogs = Dictionary(
            before.logs.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.reviewedAt >= rhs.reviewedAt ? lhs : rhs }
        )
        let afterLogs = Dictionary(
            store.logs.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.reviewedAt >= rhs.reviewedAt ? lhs : rhs }
        )
        for id in Set(beforeLogs.keys).union(afterLogs.keys).filter({ beforeLogs[$0] != afterLogs[$0] }) {
            if let log = afterLogs[id] {
                let object = try (logByID[id] ?? Self.insert(CDReviewLog.self, entityName: "CDReviewLog", in: context))
                object.uuid = id
                object.cardUUID = log.cardID
                object.deckUUID = log.deckID
                object.reviewedAt = log.reviewedAt
                object.durationMs = Int32(log.durationMs)
                object.gradeRaw = log.grade.rawValue
                object.prevStateRaw = log.previous.state.rawValue
                object.prevStability = log.previous.stability
                object.prevDifficulty = log.previous.difficulty
                object.prevDueAt = log.previous.dueAt
                object.prevLastReviewedAt = log.previous.lastReviewedAt
                object.prevReps = Int32(log.previous.reps)
                object.prevLapses = Int32(log.previous.lapses)
                object.scheduledDays = Int32(log.scheduledDays)
                object.elapsedDays = Int32(log.elapsedDays)
                object.revokedAt = log.revokedAt
            } else {
                for object in logs where object.uuid == id { context.delete(object) }
            }
        }

        let batches = try context.fetch(CDImportBatch.fetchRequest())
        let batchByID = try deterministicMap(
            batches,
            id: \.uuid,
            updatedAt: \.updatedAt,
            tie: { "\($0.importedAt?.timeIntervalSinceReferenceDate ?? .nan)|\($0.sourceName)" }
        )
        let batchIDs = Set(before.importBatches.keys).union(store.importBatches.keys).filter {
            before.importBatches[$0] != store.importBatches[$0]
        }
        for id in batchIDs {
            if let batch = store.importBatches[id] {
                let object = try (
                    batchByID[id] ?? Self.insert(CDImportBatch.self, entityName: "CDImportBatch", in: context)
                )
                object.uuid = id
                object.sourceName = batch.sourceName
                object.importedAt = batch.importedAt
                object.createdNoteUUIDsJSON = String(
                    data: try encoder.encode(batch.createdNoteIDs),
                    encoding: .utf8
                ) ?? "[]"
                object.destinationDeckUUID = batch.destinationDeckID
                object.destinationWasNewDeck = batch.destinationWasNewDeck
                object.duplicateRowsJSON = "[]"
                object.rejectedRowsJSON = "[]"
                object.undoneAt = batch.undoneAt
            } else {
                for object in batches where object.uuid == id { context.delete(object) }
            }
        }

        if before.settings != store.settings {
            let existing = try context.fetch(CDStudySettings.fetchRequest())
                .filter { $0.singletonKey == "primary" }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            let settings = try (existing.first
                ?? Self.insert(CDStudySettings.self, entityName: "CDStudySettings", in: context))
            settings.uuid = settings.uuid ?? UUID()
            settings.singletonKey = "primary"
            settings.appearanceRaw = store.settings.appearance.rawValue
            settings.newPerDay = Int32(store.settings.newPerDay)
            settings.reviewsPerDay = Int32(store.settings.reviewsPerDay)
            settings.reminderEnabled = store.settings.reminder.isEnabled
            settings.reminderHour = Int16(store.settings.reminder.hour)
            settings.reminderMinute = Int16(store.settings.reminder.minute)
        }
    }

    static func applyTags(_ names: [String], to note: CDNote, context: NSManagedObjectContext) throws {
        let existing = try context.fetch(CDTag.fetchRequest())
        var byName = existing.reduce(into: [String: CDTag]()) { result, tag in
            let normalized = tag.normalizedName
            if let current = result[normalized] {
                let currentDate = current.updatedAt ?? .distantPast
                let tagDate = tag.updatedAt ?? .distantPast
                let currentID = current.uuid?.uuidString ?? ""
                let tagID = tag.uuid?.uuidString ?? ""
                if currentDate > tagDate || (currentDate == tagDate && currentID >= tagID) { return }
            }
            result[normalized] = tag
        }
        let tags = try TagNormalizer.canonicalize(names).map { name -> CDTag in
            let normalized = TagNormalizer.normalize(name)
            let tag = try (byName[normalized]
                ?? Self.insert(CDTag.self, entityName: "CDTag", in: context))
            byName[normalized] = tag
            tag.name = name
            tag.normalizedName = normalized
            tag.deletedAt = nil
            return tag
        }
        note.tags = NSSet(array: tags)
    }

    static func decodeStrings(_ string: String) throws -> [String] {
        guard let data = string.data(using: .utf8) else { throw CoreDataMappingError.malformedPersistedData }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw CoreDataMappingError.malformedPersistedData
        }
    }

    static func decodeUUIDs(_ string: String) throws -> [UUID] {
        guard let data = string.data(using: .utf8) else { throw CoreDataMappingError.malformedPersistedData }
        do {
            return try JSONDecoder().decode([UUID].self, from: data)
        } catch {
            throw CoreDataMappingError.malformedPersistedData
        }
    }

    private static func deterministicMap<Object: NSManagedObject>(
        _ objects: [Object],
        id: (Object) -> UUID?,
        updatedAt: (Object) -> Date?,
        tie: (Object) -> String
    ) throws -> [UUID: Object] {
        var result: [UUID: Object] = [:]
        var keys: [UUID: String] = [:]
        for object in objects {
            guard let objectID = id(object), let date = updatedAt(object) else {
                throw CoreDataMappingError.malformedPersistedData
            }
            let objectKey = tie(object)
            guard let current = result[objectID], let currentDate = updatedAt(current) else {
                result[objectID] = object
                keys[objectID] = objectKey
                continue
            }
            if date == currentDate {
                // A tie key is only a stable ordering. It must never silently choose one
                // divergent payload: equal timestamps with different domain fields are
                // ambiguous persisted state and require a typed recovery path.
                guard canonicalPayload(object) == canonicalPayload(current) else {
                    throw CoreDataMappingError.malformedPersistedData
                }
            }
            if date > currentDate || (date == currentDate && objectKey > (keys[objectID] ?? "")) {
                result[objectID] = object
                keys[objectID] = objectKey
            }
        }
        return result
    }

    private static func canonicalPayload(_ object: NSManagedObject) -> String {
        let attributes = object.entity.attributesByName.keys.sorted().map { key in
            "a:\(key)=\(canonicalValue(object.value(forKey: key)))"
        }
        let relationships = object.entity.relationshipsByName.keys.sorted().map { key in
            let value = object.value(forKey: key)
            if let related = value as? NSManagedObject {
                return "r:\(key)=\(canonicalValue(related.value(forKey: "uuid")))"
            }
            if let related = value as? NSSet {
                let values = related.compactMap { ($0 as? NSManagedObject)?.value(forKey: "uuid") }
                    .map(canonicalValue)
                    .sorted()
                    .joined(separator: ",")
                return "r:\(key)=[\(values)]"
            }
            return "r:\(key)=\(canonicalValue(value))"
        }
        return (attributes + relationships).joined(separator: "|")
    }

    private static func canonicalValue(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull:
            return "nil"
        case let value as UUID:
            return value.uuidString
        case let value as Date:
            return String(format: "%.17g", value.timeIntervalSinceReferenceDate)
        case let value as Data:
            return value.base64EncodedString()
        case let value as NSNumber:
            return value.stringValue
        case let value as String:
            return value
        default:
            return String(describing: value)
        }
    }

    static func deckSummaries(store: LibraryStore, now: Date) -> [DeckSummary] {
        store.liveDecks.map { deck in
            let candidates = store.candidates(in: .deck(deck.id))
            let upcoming = InMemoryLibrary.upcomingCounts(candidates: candidates, now: now)
            return DeckSummary(
                deck: deck,
                dueCount: QueueBuilder.dueCount(candidates: candidates, now: now),
                newCount: QueueBuilder.newCount(candidates: candidates, now: now),
                tomorrowCount: upcoming.tomorrow,
                thisWeekCount: upcoming.thisWeek,
                laterCount: upcoming.later,
                suspendedCount: candidates.filter { $0.schedule?.suspendedAt != nil }.count,
                totalCards: candidates.count
            )
        }
    }

    static func summaries(store: LibraryStore, notes: [Note], filters: SearchFilters, now: Date) -> [NoteSummary] {
        notes.filter { matches(store: store, note: $0, filters: filters, now: now) }
            .map { note in
                let states = store.cards(forNote: note.id).map { store.schedules[$0.id] }
                return NoteSummary(
                    note: note,
                    cardCount: states.count,
                    dueCount: states.filter { ($0?.dueAt).map { $0 <= now } ?? false }.count,
                    isNew: states.allSatisfy { $0?.isUnseen ?? true },
                    isSuspended: states.contains { $0?.isSuspended ?? false },
                    isBuried: states.contains { $0?.isBuried(at: now) ?? false }
                )
            }
            .sorted { lhs, rhs in
                switch filters.sorting {
                case .updated: lhs.note.updatedAt > rhs.note.updatedAt
                case .created: lhs.note.createdAt > rhs.note.createdAt
                case .name: lhs.note.front.localizedCaseInsensitiveCompare(rhs.note.front) == .orderedAscending
                }
            }
    }

    static func matches(store: LibraryStore, note: Note, filters: SearchFilters, now: Date) -> Bool {
        let query = filters.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let haystack = [note.front, note.back ?? ""] + note.tags
        if !query.isEmpty && !haystack.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return false
        }
        if let type = filters.type, note.type != type { return false }
        switch filters.state {
        case .any: return true
        case .new: return store.cards(forNote: note.id).allSatisfy { store.schedules[$0.id] == nil }
        case .due: return store.cards(forNote: note.id).contains { card in
            guard let state = store.schedules[card.id], !state.isSuspended, !state.isBuried(at: now) else { return false }
            return state.dueAt <= now
        }
        case .suspended: return store.cards(forNote: note.id).contains { store.schedules[$0.id]?.isSuspended ?? false }
        case .buried: return store.cards(forNote: note.id).contains { store.schedules[$0.id]?.isBuried(at: now) ?? false }
        }
    }

    static func backup(from store: LibraryStore, appVersion: String, now: Date) -> BackupDocument {
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
                        cards: store.cards(forNote: note.id).map { BackupCard(uuid: $0.id, templateKey: $0.templateKey) },
                        mediaIDs: note.mediaIDs
                    )
                }
            )
        }
        let cardIDs = Set(backupDecks.flatMap { $0.notes.flatMap { $0.cards.map(\.uuid) } })
        return BackupDocument(
            appVersion: appVersion,
            exportedAt: now,
            settings: store.settings,
            decks: backupDecks,
            schedules: store.schedules
                .filter { cardIDs.contains($0.key) }
                .map { BackupSchedule(cardUUID: $0.key, state: $0.value) },
            reviewLogs: store.logs.filter { deckIDs.contains($0.deckID) }.map(BackupReviewLog.init)
        )
    }

    static func restoreNote(_ backupNote: BackupNote, into deckID: UUID, store: inout LibraryStore) -> Bool {
        guard store.notes[backupNote.uuid] == nil else { return false }
        let note = Note(
            id: backupNote.uuid,
            deckID: deckID,
            type: backupNote.type,
            front: backupNote.front,
            back: backupNote.back,
            tags: backupNote.tags,
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

    static func restoreProgress(
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
        let known = Set(store.logs.map(\.id))
        var added = 0
        for backupLog in document.reviewLogs where !known.contains(backupLog.uuid) {
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
}
