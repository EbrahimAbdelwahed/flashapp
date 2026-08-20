import Foundation
import Testing
@testable import FlashUpData

@Suite("Remote history processing", .serialized)
struct RemoteChangeProcessorTests {
    @Test("History resumes from the persisted token and deduplicates deterministically")
    // The fixture setup is intentionally kept in one test so token/replay ordering stays clear.
    // swiftlint:disable:next function_body_length
    func tokenResumeAndDeduplication() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-history-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tokenURL = root.appendingPathComponent("history.token")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = RemoteHistoryTransaction(
            identifier: "store|1",
            transactionNumber: 1,
            timestamp: Date(timeIntervalSince1970: 100),
            token: Data([1]),
            changes: [RemoteHistoryChange(
                changeID: 2,
                entityName: "CDSchedule",
                objectURI: "x-coredata://schedule",
                changeType: .update
            )]
        )
        let second = RemoteHistoryTransaction(
            identifier: "store|2",
            transactionNumber: 2,
            timestamp: Date(timeIntervalSince1970: 200),
            token: Data([2]),
            changes: [RemoteHistoryChange(
                changeID: 3,
                entityName: "CDReviewLog",
                objectURI: "x-coredata://log",
                changeType: .insert
            )]
        )
        let probe = HistoryProbe(transactions: [first, first, second])
        let replayed = HistoryProbe(transactions: [])
        let processor = RemoteChangeProcessor(
            tokenURL: tokenURL,
            fetchHistory: { token in
                replayed.seenTokens.append(token)
                return probe.transactions
            },
            replay: { transactions in
                replayed.replayedTransactions = transactions
            },
            replaySchedule: { changes in
                replayed.replayedChanges = changes
            }
        )

        let result = try await processor.processNow()
        #expect(result.transactionCount == 2)
        #expect(result.deduplicatedTransactionCount == 1)
        #expect(result.changeCount == 2)
        #expect(replayed.replayedTransactions.map(\.identifier) == ["store|1", "store|2"])
        #expect(replayed.replayedChanges.map(\.entityName) == ["CDReviewLog", "CDSchedule"])
        #expect(await processor.currentToken() == Data([2]))

        let resumedProbe = HistoryProbe(transactions: [])
        let resumed = RemoteChangeProcessor(
            tokenURL: tokenURL,
            fetchHistory: { token in
                resumedProbe.seenTokens.append(token)
                return []
            },
            replay: { _ in }
        )
        _ = try await resumed.processNow()
        #expect(resumedProbe.seenTokens == [Data([2])])
    }

    @Test("Remote-change notifications debounce into one history read")
    func notificationDebounce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-history-debounce", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = HistoryProbe(transactions: [])
        let processor = RemoteChangeProcessor(
            tokenURL: root.appendingPathComponent("history.token"),
            debounceNanoseconds: 10_000_000,
            fetchHistory: { _ in
                probe.fetchCount += 1
                return []
            },
            replay: { _ in }
        )

        await processor.notifyRemoteChange()
        await processor.notifyRemoteChange()
        await processor.notifyRemoteChange()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(probe.fetchCount == 1)
    }

    @Test("Conflicting duplicate transaction IDs fail instead of choosing a winner")
    func conflictingDuplicateFails() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-history-conflict", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = RemoteHistoryTransaction(
            identifier: "same",
            transactionNumber: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            token: Data([1]),
            changes: []
        )
        let second = RemoteHistoryTransaction(
            identifier: "same",
            transactionNumber: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            token: Data([2]),
            changes: []
        )
        let processor = RemoteChangeProcessor(
            tokenURL: root.appendingPathComponent("history.token"),
            fetchHistory: { _ in [first, second] },
            replay: { _ in }
        )

        await #expect(throws: RemoteChangeProcessorError.nondeterministicDuplicate) {
            _ = try await processor.processNow()
        }
        #expect(await processor.currentToken() == nil)
    }
}

private final class HistoryProbe: @unchecked Sendable {
    let transactions: [RemoteHistoryTransaction]
    var seenTokens: [Data?] = []
    var replayedTransactions: [RemoteHistoryTransaction] = []
    var replayedChanges: [RemoteHistoryChange] = []
    var fetchCount = 0

    init(transactions: [RemoteHistoryTransaction]) {
        self.transactions = transactions
    }
}
