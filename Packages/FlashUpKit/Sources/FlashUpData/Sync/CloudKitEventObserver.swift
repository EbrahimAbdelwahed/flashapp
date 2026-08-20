import CoreData
import Foundation

extension CoreDataLibraryRepository {
    /// Registers the event observer against the owned container. The resolver argument keeps
    /// notification filtering and lifecycle handling deterministic in tests without inventing
    /// CloudKit event instances that Apple only creates internally.
    internal static func observeCloudKitEvents(
        for container: NSPersistentCloudKitContainer,
        monitor: SyncMonitor,
        center: NotificationCenter = .default,
        eventResolver: ((Notification) -> SyncMonitorEvent?)? = nil
    ) -> NSObjectProtocol {
        let resolveEvent = eventResolver ?? Self.syncMonitorEvent
        return center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { notification in
            guard let event = resolveEvent(notification) else { return }
            Task { await monitor.handle(event) }
        }
    }

    private static func syncMonitorEvent(
        from notification: Notification
    ) -> SyncMonitorEvent? {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return nil }
        let type: SyncMonitorEventType
        switch event.type {
        case .export: type = .export
        case .import: type = .import
        case .setup: type = .setup
        @unknown default:
            return nil
        }
        return SyncMonitorEvent(type: type, endDate: event.endDate, succeeded: event.succeeded)
    }
}
