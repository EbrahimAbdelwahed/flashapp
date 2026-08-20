import CloudKit
import CoreData
import FlashUpDomain
import Foundation

public extension PersistenceController {
    /// Device-local cursor for the history processor. It is intentionally separate from the
    /// user store and never contains card content.
    var historyTokenURL: URL {
        Self.historyTokenURL(for: configuration.storeURL)
    }

    /// Reads Core Data's persistent history as metadata-only records. The processor persists
    /// the opaque token after replay succeeds, so a failed hook is retried on the next pass.
    func fetchPersistentHistory(after tokenData: Data?) throws -> [RemoteHistoryTransaction] {
        let token = try Self.decodeHistoryToken(tokenData)
        do {
            return try performBackgroundTask { context in
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
                request.resultType = .transactionsAndChanges
                guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    return []
                }
                return try transactions.map(Self.historyRecord)
            }
        } catch let error as RemoteChangeProcessorError {
            throw error
        } catch {
            throw RemoteChangeProcessorError.historyReadFailed
        }
    }

    /// Refreshes registered objects without discarding unsaved local edits. New and deleted
    /// objects are picked up by the next repository read against its fresh background context.
    func mergePersistentHistory(_ records: [RemoteHistoryTransaction]) throws {
        guard !records.isEmpty else { return }
        var objectURIs = Set<String>()
        for record in records {
            objectURIs.formUnion(record.changes.map(\.objectURI))
        }
        viewContext.performAndWait {
            for uriString in objectURIs {
                guard let uri = URL(string: uriString),
                      let objectID = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: uri),
                      let object = viewContext.registeredObject(for: objectID),
                      !object.hasChanges,
                      !object.isDeleted else { continue }
                viewContext.refresh(object, mergeChanges: true)
            }
        }
    }

    /// Applies the deterministic convergence pass after CloudKit has imported rows. The
    /// imported rows are already in the SQLite store; this pass only resolves the two entity
    /// classes that intentionally have no CloudKit uniqueness constraint and rebuilds schedules
    /// from append-only review logs. It never reads or emits card text.
    func reconcileRemoteHistory(
        _ records: [RemoteHistoryTransaction],
        using scheduler: FSRSService
    ) throws {
        guard !records.isEmpty else { return }
        try performBackgroundTask { context in
            try Self.deduplicateTags(in: context)
            try Self.replaySchedules(in: context, using: scheduler)
        }
        try mergePersistentHistory(records)
    }

    /// Bounds the on-device history journal while retaining the opaque cursor used by the
    /// processor. CloudKit's store remains authoritative for future imports.
    func deletePersistentHistory(olderThan date: Date) throws {
        do {
            try performBackgroundTask { context in
                let request = NSPersistentHistoryChangeRequest.deleteHistory(before: date)
                _ = try context.execute(request)
            }
        } catch let error as RemoteChangeProcessorError {
            throw error
        } catch {
            throw RemoteChangeProcessorError.historyReadFailed
        }
    }
}

private extension PersistenceController {
    static func historyTokenURL(for storeURL: URL?) -> URL {
        if let storeURL {
            return storeURL.deletingPathExtension()
                .appendingPathExtension("history-token")
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashApp-history-\(UUID().uuidString).token")
    }

    static func decodeHistoryToken(_ data: Data?) throws -> NSPersistentHistoryToken? {
        guard let data else { return nil }
        do {
            guard let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            ) else {
                throw RemoteChangeProcessorError.invalidToken
            }
            return token
        } catch let error as RemoteChangeProcessorError {
            throw error
        } catch {
            throw RemoteChangeProcessorError.invalidToken
        }
    }

    static func encodeHistoryToken(_ token: NSPersistentHistoryToken) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        } catch {
            throw RemoteChangeProcessorError.invalidToken
        }
    }

    static func historyRecord(_ transaction: NSPersistentHistoryTransaction) throws -> RemoteHistoryTransaction {
        let changes = (transaction.changes ?? []).map { change in
            RemoteHistoryChange(
                changeID: change.changeID,
                entityName: change.changedObjectID.entity.name ?? "",
                objectURI: change.changedObjectID.uriRepresentation().absoluteString,
                changeType: Self.changeType(for: change.changeType),
                updatedProperties: change.updatedProperties?.map(\.name) ?? []
            )
        }
        return RemoteHistoryTransaction(
            identifier: "\(transaction.storeID)|\(transaction.transactionNumber)",
            transactionNumber: transaction.transactionNumber,
            timestamp: transaction.timestamp,
            token: try encodeHistoryToken(transaction.token),
            changes: changes
        )
    }

    static func changeType(for changeType: NSPersistentHistoryChangeType) -> RemoteHistoryChangeType {
        switch changeType {
        case .insert: .insert
        case .update: .update
        case .delete: .delete
        @unknown default: .update
        }
    }

    static func deduplicateTags(in context: NSManagedObjectContext) throws {
        let tags = try context.fetch(CDTag.fetchRequest())
        let groups = Dictionary(grouping: tags) { $0.normalizedName }
        for candidates in groups.values where candidates.count > 1 {
            let ordered = candidates.sorted { lhs, rhs in
                (lhs.uuid?.uuidString ?? "") < (rhs.uuid?.uuidString ?? "")
            }
            guard let winner = ordered.first else { continue }
            for loser in ordered.dropFirst() {
                let notes = loser.notes?.allObjects as? [CDNote] ?? []
                for note in notes {
                    var merged = (note.tags?.allObjects as? [CDTag] ?? [])
                        .filter { $0 !== loser }
                    if !merged.contains(where: { $0 === winner }) { merged.append(winner) }
                    merged.sort { lhs, rhs in
                        let left = [lhs.normalizedName, lhs.name, lhs.uuid?.uuidString ?? ""]
                            .joined(separator: "|")
                        let right = [rhs.normalizedName, rhs.name, rhs.uuid?.uuidString ?? ""]
                            .joined(separator: "|")
                        return left < right
                    }
                    note.tags = NSSet(array: merged)
                    let names = merged.map(\.name)
                    note.tagsJSON = String(
                        data: try JSONEncoder().encode(names),
                        encoding: .utf8
                    ) ?? "[]"
                }
                context.delete(loser)
            }
        }
    }

    static func replaySchedules(in context: NSManagedObjectContext, using scheduler: FSRSService) throws {
        var winners = try Self.deduplicateSchedules(in: context)
        let logsByCard = try Self.reviewLogsByCard(in: context)

        for (cardID, cardLogs) in logsByCard {
            let orderedLogs = cardLogs.sorted {
                $0.reviewedAt == $1.reviewedAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.reviewedAt < $1.reviewedAt
            }
            guard let initialDueAt = orderedLogs.first?.reviewedAt else { continue }
            let schedule: CDSchedule
            if let existing = winners[cardID] {
                schedule = existing
            } else {
                guard let card = try context.fetch(CDCard.fetchRequest()).first(where: { $0.uuid == cardID }) else {
                    continue
                }
                schedule = CDSchedule(context: context)
                schedule.cardUUID = cardID
                schedule.deckUUID = card.note?.deck?.uuid
                schedule.dueAt = initialDueAt
                winners[cardID] = schedule
            }
            let flags = Self.reviewState(from: schedule)
            guard let replayed = ScheduleReplayer.replay(
                logs: orderedLogs,
                using: scheduler,
                initialDueAt: initialDueAt
            ) else { continue }
            Self.apply(replayed.carryingUserFlags(from: flags), to: schedule)
        }
    }

    static func deduplicateSchedules(in context: NSManagedObjectContext) throws -> [UUID: CDSchedule] {
        let schedules = try context.fetch(CDSchedule.fetchRequest())
        var winners: [UUID: CDSchedule] = [:]
        for schedule in schedules {
            guard let cardID = schedule.cardUUID else { continue }
            guard let current = winners[cardID] else {
                winners[cardID] = schedule
                continue
            }
            let currentID = current.uuid?.uuidString ?? ""
            let scheduleID = schedule.uuid?.uuidString ?? ""
            if scheduleID < currentID {
                context.delete(current)
                winners[cardID] = schedule
            } else {
                context.delete(schedule)
            }
        }
        return winners
    }

    static func reviewLogsByCard(in context: NSManagedObjectContext) throws -> [UUID: [ReviewLog]] {
        let logs = try context.fetch(CDReviewLog.fetchRequest())
        var logsByCard: [UUID: [ReviewLog]] = [:]
        for log in logs {
            guard let reviewLog = try Self.reviewLog(from: log) else { continue }
            logsByCard[reviewLog.cardID, default: []].append(reviewLog)
        }
        return logsByCard
    }

    static func reviewLog(from object: CDReviewLog) throws -> ReviewLog? {
        guard let id = object.uuid,
              let cardID = object.cardUUID,
              let deckID = object.deckUUID,
              let reviewedAt = object.reviewedAt,
              let grade = Grade(rawValue: object.gradeRaw),
              let state = ScheduleState(rawValue: object.prevStateRaw),
              let previousDueAt = object.prevDueAt else {
            return nil
        }
        return ReviewLog(
            id: id,
            cardID: cardID,
            deckID: deckID,
            reviewedAt: reviewedAt,
            durationMs: Int(object.durationMs),
            grade: grade,
            previous: ReviewState(
                state: state,
                stability: object.prevStability,
                difficulty: object.prevDifficulty,
                dueAt: previousDueAt,
                lastReviewedAt: object.prevLastReviewedAt,
                reps: Int(object.prevReps),
                lapses: Int(object.prevLapses)
            ),
            scheduledDays: Int(object.scheduledDays),
            elapsedDays: Int(object.elapsedDays),
            revokedAt: object.revokedAt
        )
    }

    static func reviewState(from object: CDSchedule) -> ReviewState {
        ReviewState(
            state: ScheduleState(rawValue: object.stateRaw) ?? .new,
            stability: object.stability,
            difficulty: object.difficulty,
            dueAt: object.dueAt ?? .distantPast,
            lastReviewedAt: object.lastReviewedAt,
            reps: Int(object.reps),
            lapses: Int(object.lapses),
            suspendedAt: object.suspendedAt,
            buriedUntil: object.buriedUntil
        )
    }

    static func apply(_ state: ReviewState, to object: CDSchedule) {
        object.stateRaw = state.state.rawValue
        object.stability = state.stability
        object.difficulty = state.difficulty
        object.dueAt = state.dueAt
        object.lastReviewedAt = state.lastReviewedAt
        object.reps = Int32(state.reps)
        object.lapses = Int32(state.lapses)
        object.suspendedAt = state.suspendedAt
        object.buriedUntil = state.buriedUntil
    }
}
