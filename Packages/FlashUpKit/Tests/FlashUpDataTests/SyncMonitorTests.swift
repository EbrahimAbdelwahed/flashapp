import CoreData
import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

@Suite("Private sync status", .serialized)
struct SyncMonitorTests {
    @Test("Account states map to truthful user-facing statuses")
    func accountStateMapping() async {
        let cases: [(SyncAccountState, SyncStatus)] = [
            (.available, .upToDate(lastSyncedAt: nil)),
            (.noAccount, .accountUnavailable),
            (.restricted, .accountUnavailable),
            (.temporarilyUnavailable, .offline),
            (.localOnly, .offline),
            (.couldNotDetermine, .failed(reason: "iCloud account status is unavailable."))
        ]

        for (accountState, expectedStatus) in cases {
            let monitor = SyncMonitor(initialAccountState: accountState)
            #expect((await monitor.snapshot()).status == expectedStatus)
        }
    }

    @Test("A retry refreshes availability without fabricating success")
    func retryRefreshesAvailability() async {
        let monitor = SyncMonitor(
            initialAccountState: .noAccount,
            accountStatusProvider: { .noAccount }
        )

        let unavailable = await monitor.refreshAccountStatus()
        #expect(unavailable.accountState == .noAccount)
        #expect(unavailable.status == .accountUnavailable)

        let availableMonitor = SyncMonitor(
            initialAccountState: .noAccount,
            accountStatusProvider: { .available }
        )
        let available = await availableMonitor.refreshAccountStatus()
        #expect(available.accountState == .available)
        #expect(available.status == .upToDate(lastSyncedAt: nil))
    }

    @Test("Syncing and last-synced transitions are constrained by account availability")
    func syncingTransitions() async {
        let unavailable = SyncMonitor(initialAccountState: .restricted)
        #expect((await unavailable.markSyncing()).status == .accountUnavailable)

        let monitor = SyncMonitor(initialAccountState: .available)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect((await monitor.markSyncing()).status == .syncing)
        let synced = await monitor.markSynchronized(at: date)
        #expect(synced.status == .upToDate(lastSyncedAt: date))
        #expect(synced.lastSyncedAt == date)
    }

    @Test("Account-status provider failures stay visibly failed")
    func providerFailure() async {
        let monitor = SyncMonitor(
            initialAccountState: .available,
            accountStatusProvider: { throw TestError.unavailable }
        )

        let snapshot = await monitor.refreshAccountStatus()
        #expect(snapshot.accountState == .couldNotDetermine)
        #expect(snapshot.status == .failed(reason: "iCloud account status is unavailable."))
    }

    @Test("A completed CloudKit event is the only monitor path that records a sync time")
    func completedEventRecordsSyncTime() async {
        let monitor = SyncMonitor(initialAccountState: .available)
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        #expect((await monitor.markSyncing()).status == .syncing)
        #expect((await monitor.markImportSucceeded(at: date)).status == .upToDate(lastSyncedAt: date))
    }

    @Test("CloudKit event observer filters its container and tracks start-to-completion")
    func cloudKitEventObserverLifecycle() async throws {
        let controller = try PersistenceController(configuration: .inMemory)
        defer { try? controller.close() }
        let monitor = SyncMonitor(initialAccountState: .available)
        let center = NotificationCenter()
        let pending = SyncMonitorEvent(type: .export, endDate: nil, succeeded: false)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_456)
        let completed = SyncMonitorEvent(type: .export, endDate: completedAt, succeeded: true)
        var currentEvent = pending
        let observer = CoreDataLibraryRepository.observeCloudKitEvents(
            for: controller.container,
            monitor: monitor,
            center: center,
            eventResolver: { _ in currentEvent }
        )
        defer { center.removeObserver(observer) }

        center.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: NSObject()
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect((await monitor.snapshot()).status == .upToDate(lastSyncedAt: nil))

        center.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: controller.container
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect((await monitor.snapshot()).status == .syncing)

        currentEvent = completed
        center.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: controller.container
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect((await monitor.snapshot()).status == .upToDate(lastSyncedAt: completedAt))
    }
}

private enum TestError: Error {
    case unavailable
}
