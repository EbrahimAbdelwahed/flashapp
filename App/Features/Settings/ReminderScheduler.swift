import FlashUpDomain
import Foundation
import OSLog
import UserNotifications

/// Schedules the daily study reminder (spec §A11.4).
///
/// Authorization is only requested when the user turns the reminder on — never at launch —
/// so the permission prompt always arrives with an obvious reason attached.
protocol ReminderScheduling: Sendable {
    /// Applies `reminder`, requesting authorization if needed.
    ///
    /// - Returns: `true` when a notification is actually scheduled. A `false` result never
    ///   rewrites the user's choice — the switch stays where they put it and the screen
    ///   explains that iOS is holding notifications back, which is the thing they can act on.
    @discardableResult
    func apply(_ reminder: StudySettings.Reminder) async -> Bool
}

struct ReminderScheduler: ReminderScheduling {
    static let identifier = "com.flashup.app.dailyReminder"

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: AppEnvironment.loggingSubsystem, category: "reminder")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func apply(_ reminder: StudySettings.Reminder) async -> Bool {
        guard reminder.isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            return true
        }

        guard await requestAuthorization() else {
            logger.notice("Reminder authorization refused")
            return false
        }

        await schedule(reminder)
        return true
    }

    private func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    private func schedule(_ reminder: StudySettings.Reminder) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "reminder.title")
        content.body = String(localized: "reminder.body")
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            // Repeats daily at the chosen time, in the user's own calendar.
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        do {
            try await center.add(request)
            logger.info("Daily reminder scheduled")
        } catch {
            logger.error("Could not schedule the reminder: \(error.localizedDescription, privacy: .public)")
        }
    }
}
