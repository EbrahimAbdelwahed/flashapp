import Foundation

public enum RemoteHistoryChangeType: Int, Equatable, Sendable {
    case insert = 0
    case update = 1
    case delete = 2
}

/// Metadata extracted from persistent history. It intentionally contains object identity and
/// changed-property names only; card text and other user content never enter this pipeline.
public struct RemoteHistoryChange: Equatable, Sendable {
    public let changeID: Int64
    public let entityName: String
    public let objectURI: String
    public let changeType: RemoteHistoryChangeType
    public let updatedProperties: [String]

    public init(
        changeID: Int64,
        entityName: String,
        objectURI: String,
        changeType: RemoteHistoryChangeType,
        updatedProperties: [String] = []
    ) {
        self.changeID = changeID
        self.entityName = entityName
        self.objectURI = objectURI
        self.changeType = changeType
        self.updatedProperties = updatedProperties.sorted()
    }
}

public struct RemoteHistoryTransaction: Equatable, Sendable {
    public let identifier: String
    public let transactionNumber: Int64
    public let timestamp: Date
    public let token: Data
    public let changes: [RemoteHistoryChange]

    public init(
        identifier: String,
        transactionNumber: Int64,
        timestamp: Date,
        token: Data,
        changes: [RemoteHistoryChange]
    ) {
        self.identifier = identifier
        self.transactionNumber = transactionNumber
        self.timestamp = timestamp
        self.token = token
        self.changes = changes.sorted { lhs, rhs in
            if lhs.changeID != rhs.changeID { return lhs.changeID < rhs.changeID }
            if lhs.entityName != rhs.entityName { return lhs.entityName < rhs.entityName }
            return lhs.objectURI < rhs.objectURI
        }
    }
}

public struct RemoteProcessingResult: Equatable, Sendable {
    public let transactionCount: Int
    public let changeCount: Int
    public let deduplicatedTransactionCount: Int

    public init(transactionCount: Int, changeCount: Int, deduplicatedTransactionCount: Int) {
        self.transactionCount = transactionCount
        self.changeCount = changeCount
        self.deduplicatedTransactionCount = deduplicatedTransactionCount
    }
}

public enum RemoteChangeProcessorError: Error, Equatable, Sendable, LocalizedError {
    case invalidToken
    case nondeterministicDuplicate
    case historyReadFailed
    case replayFailed

    public var errorDescription: String? {
        switch self {
        case .invalidToken: "The FlashApp sync history token is invalid."
        case .nondeterministicDuplicate: "The FlashApp sync history contains a conflicting duplicate."
        case .historyReadFailed: "The FlashApp sync history could not be read."
        case .replayFailed: "The FlashApp sync history could not be applied."
        }
    }
}

/// Persists a Core Data history cursor and applies remote changes in a stable order.
///
/// The processor is deliberately independent from CloudKit account state. A missing account
/// pauses availability, while this local cursor remains valid for the next retry.
public actor RemoteChangeProcessor {
    public typealias HistoryFetcher = @Sendable (Data?) throws -> [RemoteHistoryTransaction]
    public typealias ReplayHook = @Sendable ([RemoteHistoryTransaction]) throws -> Void
    public typealias ScheduleReplayHook = @Sendable ([RemoteHistoryChange]) throws -> Void
    public typealias PostReplayHook = @Sendable () throws -> Void

    private let tokenURL: URL
    private let fetchHistory: HistoryFetcher
    private let replay: ReplayHook
    private let replaySchedule: ScheduleReplayHook?
    private let postReplay: PostReplayHook?
    private let debounceNanoseconds: UInt64
    private var tokenData: Data?
    private var pendingNotification = false
    private var debounceTask: Task<Void, Never>?
    private var lastError: RemoteChangeProcessorError?
    private var closed = false

    public init(
        tokenURL: URL,
        debounceNanoseconds: UInt64 = 2_000_000_000,
        fetchHistory: @escaping HistoryFetcher,
        replay: @escaping ReplayHook,
        replaySchedule: ScheduleReplayHook? = nil,
        postReplay: PostReplayHook? = nil
    ) {
        self.tokenURL = tokenURL
        self.debounceNanoseconds = debounceNanoseconds
        self.fetchHistory = fetchHistory
        self.replay = replay
        self.replaySchedule = replaySchedule
        self.postReplay = postReplay
        do {
            self.tokenData = try Self.loadToken(at: tokenURL)
            self.lastError = nil
        } catch {
            self.tokenData = nil
            self.lastError = .invalidToken
        }
    }

    public func currentToken() -> Data? { tokenData }
    public func lastProcessingError() -> RemoteChangeProcessorError? { lastError }

    /// Cancels debounced work when its owning repository is closed for account routing.
    /// No history/convergence behavior changes; subsequent notifications are ignored.
    public func close() {
        closed = true
        debounceTask?.cancel()
        debounceTask = nil
        pendingNotification = false
    }

    /// Processes all history after the persisted cursor. It is safe to call repeatedly: the
    /// cursor advances only after replay and schedule hooks both succeed.
    @discardableResult
    public func processNow() throws -> RemoteProcessingResult {
        guard !closed else {
            return RemoteProcessingResult(transactionCount: 0, changeCount: 0, deduplicatedTransactionCount: 0)
        }
        if lastError == .invalidToken { throw RemoteChangeProcessorError.invalidToken }
        let fetched: [RemoteHistoryTransaction]
        do {
            fetched = try fetchHistory(tokenData)
        } catch {
            lastError = .historyReadFailed
            throw RemoteChangeProcessorError.historyReadFailed
        }

        let transactions: [RemoteHistoryTransaction]
        do {
            transactions = try Self.deduplicated(fetched)
        } catch let error as RemoteChangeProcessorError {
            lastError = error
            throw error
        }
        let changes = Self.deduplicatedChanges(in: transactions)
        do {
            try replay(transactions)
            try replaySchedule?(changes)
        } catch {
            lastError = .replayFailed
            throw RemoteChangeProcessorError.replayFailed
        }

        if let latest = transactions.last {
            do {
                try Self.persistToken(latest.token, at: tokenURL)
                tokenData = latest.token
            } catch {
                lastError = .historyReadFailed
                throw RemoteChangeProcessorError.historyReadFailed
            }
            do {
                try postReplay?()
            } catch {
                lastError = .historyReadFailed
                throw RemoteChangeProcessorError.historyReadFailed
            }
        }
        lastError = nil
        return RemoteProcessingResult(
            transactionCount: transactions.count,
            changeCount: changes.count,
            deduplicatedTransactionCount: fetched.count - transactions.count
        )
    }

    /// Receives a remote-change notification and coalesces bursts into one history read.
    public func notifyRemoteChange() {
        guard !closed else { return }
        pendingNotification = true
        debounceTask?.cancel()
        let delay = debounceNanoseconds
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await self?.processDebouncedNotification()
        }
    }

    @discardableResult
    public func flushPendingNotification() throws -> RemoteProcessingResult? {
        guard !closed else { return nil }
        debounceTask?.cancel()
        debounceTask = nil
        guard pendingNotification else { return nil }
        pendingNotification = false
        return try processNow()
    }

    private func processDebouncedNotification() {
        guard pendingNotification else { return }
        pendingNotification = false
        _ = try? processNow()
    }

    private static func deduplicated(
        _ transactions: [RemoteHistoryTransaction]
    ) throws -> [RemoteHistoryTransaction] {
        var byIdentifier: [String: RemoteHistoryTransaction] = [:]
        for transaction in transactions {
            if let existing = byIdentifier[transaction.identifier], existing != transaction {
                throw RemoteChangeProcessorError.nondeterministicDuplicate
            }
            byIdentifier[transaction.identifier] = transaction
        }
        return byIdentifier.values.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.transactionNumber != $1.transactionNumber {
                return $0.transactionNumber < $1.transactionNumber
            }
            return $0.identifier < $1.identifier
        }
    }

    private static func deduplicatedChanges(
        in transactions: [RemoteHistoryTransaction]
    ) -> [RemoteHistoryChange] {
        var byKey: [String: RemoteHistoryChange] = [:]
        for transaction in transactions {
            for change in transaction.changes {
                let key = "\(transaction.identifier)|\(change.changeID)|\(change.objectURI)"
                byKey[key] = change
            }
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.entityName != rhs.entityName { return lhs.entityName < rhs.entityName }
            if lhs.objectURI != rhs.objectURI { return lhs.objectURI < rhs.objectURI }
            return lhs.changeID < rhs.changeID
        }
    }

    private static func loadToken(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw RemoteChangeProcessorError.invalidToken }
        return data
    }

    private static func persistToken(_ data: Data, at url: URL) throws {
        guard !data.isEmpty else { throw RemoteChangeProcessorError.invalidToken }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }
}
