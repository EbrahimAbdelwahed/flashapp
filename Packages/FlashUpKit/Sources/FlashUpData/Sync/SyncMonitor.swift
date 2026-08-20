import CloudKit
import FlashUpDomain
import Foundation

/// The account states CloudKit exposes, kept separate from the user-facing status so a
/// restricted account cannot accidentally be presented as a successful sync.
public enum SyncAccountState: String, Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case localOnly
    case couldNotDetermine
}

public struct SyncSnapshot: Equatable, Sendable {
    public let accountState: SyncAccountState
    public let status: SyncStatus
    public let lastSyncedAt: Date?

    public init(accountState: SyncAccountState, status: SyncStatus, lastSyncedAt: Date?) {
        self.accountState = accountState
        self.status = status
        self.lastSyncedAt = lastSyncedAt
    }
}

enum SyncMonitorEventType: Sendable {
    case setup
    case `import`
    case export
}

struct SyncMonitorEvent: Sendable {
    let type: SyncMonitorEventType
    let endDate: Date?
    let succeeded: Bool
}

/// Owns account availability and the truthful status shown by the app.
///
/// Account transitions only update this state. They never create a new persistent store or
/// change its URL; Core Data continues to own the same local private replica.
public actor SyncMonitor {
    public typealias AccountStatusProvider = @Sendable () async throws -> SyncAccountState

    private let accountStatusProvider: AccountStatusProvider?
    private var accountState: SyncAccountState
    private var status: SyncStatus
    private var lastSyncedAt: Date?

    public init(
        initialAccountState: SyncAccountState = .couldNotDetermine,
        lastSyncedAt: Date? = nil,
        accountStatusProvider: AccountStatusProvider? = nil
    ) {
        self.accountStatusProvider = accountStatusProvider
        self.accountState = initialAccountState
        self.lastSyncedAt = lastSyncedAt
        self.status = Self.status(for: initialAccountState, lastSyncedAt: lastSyncedAt)
    }

    /// Creates the production monitor without querying CloudKit during initialization.
    /// The account is queried explicitly by `refreshAccountStatus()` or a sync retry.
    public static func cloudKit(containerIdentifier: String) -> SyncMonitor {
        SyncMonitor(
            initialAccountState: .couldNotDetermine,
            accountStatusProvider: {
                let container = CKContainer(identifier: containerIdentifier)
                return try await Self.accountState(for: container)
            }
        )
    }

    public func snapshot() -> SyncSnapshot {
        SyncSnapshot(accountState: accountState, status: status, lastSyncedAt: lastSyncedAt)
    }

    public func refreshAccountStatus() async -> SyncSnapshot {
        guard let accountStatusProvider else { return snapshot() }
        do {
            accountState = try await accountStatusProvider()
            status = Self.status(for: accountState, lastSyncedAt: lastSyncedAt)
        } catch {
            accountState = .couldNotDetermine
            status = .failed(reason: "iCloud account status is unavailable.")
        }
        return snapshot()
    }

    /// Test and event seam. It models an account transition without changing persistence.
    public func setAccountState(_ newState: SyncAccountState) -> SyncSnapshot {
        accountState = newState
        status = Self.status(for: newState, lastSyncedAt: lastSyncedAt)
        return SyncSnapshot(accountState: accountState, status: status, lastSyncedAt: lastSyncedAt)
    }

    public func markSyncing() -> SyncSnapshot {
        guard accountState == .available else { return currentSnapshot() }
        status = .syncing
        return currentSnapshot()
    }

    public func markSynchronized(at date: Date) -> SyncSnapshot {
        guard accountState == .available else { return currentSnapshot() }
        lastSyncedAt = date
        status = .upToDate(lastSyncedAt: date)
        return currentSnapshot()
    }

    /// Records a successful CloudKit export event. Local saves and history replay do not
    /// call this method because they cannot prove that the private store reached iCloud.
    public func markExportSucceeded(at date: Date) -> SyncSnapshot {
        markSynchronized(at: date)
    }

    /// Records a completed import. A successful import proves that the private replica has
    /// reached this device, so it is safe to expose the event timestamp as the last known sync
    /// time. Local saves and history processing intentionally never call this method.
    public func markImportSucceeded(at date: Date) -> SyncSnapshot {
        markSynchronized(at: date)
    }

    public func markOffline() -> SyncSnapshot {
        guard accountState == .available else { return currentSnapshot() }
        status = .offline
        return currentSnapshot()
    }

    public func markFailed(reason: String) -> SyncSnapshot {
        status = .failed(reason: reason)
        return currentSnapshot()
    }

    /// Applies the lifecycle semantics of a persistent CloudKit event. An event without an
    /// end date is still running, even when its eventual `succeeded` flag is false.
    func handle(_ event: SyncMonitorEvent) -> SyncSnapshot {
        guard let endDate = event.endDate else { return markSyncing() }
        guard event.succeeded else {
            return markFailed(reason: "iCloud sync could not be completed.")
        }
        switch event.type {
        case .setup:
            return currentSnapshot()
        case .import, .export:
            return markSynchronized(at: endDate)
        }
    }

    private func currentSnapshot() -> SyncSnapshot {
        SyncSnapshot(accountState: accountState, status: status, lastSyncedAt: lastSyncedAt)
    }

    private static func status(for accountState: SyncAccountState, lastSyncedAt: Date?) -> SyncStatus {
        switch accountState {
        case .available:
            .upToDate(lastSyncedAt: lastSyncedAt)
        case .temporarilyUnavailable:
            .offline
        case .noAccount, .restricted:
            .accountUnavailable
        case .localOnly:
            .offline
        case .couldNotDetermine:
            .failed(reason: "iCloud account status is unavailable.")
        }
    }

    private static func accountState(for container: CKContainer) async throws -> SyncAccountState {
        switch try await container.accountStatus() {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }
}
