import FlashUpDomain
import Foundation

/// Stands in for the system notification centre while UI tests run.
///
/// Without it, enabling the reminder raises the real permission alert, which is Apple's
/// dialog and not this app's behaviour. The stub lets the tests assert what Flash Up
/// actually does: keep the user's choice either way, and explain when iOS is blocking the
/// notification.
struct StubReminderScheduler: ReminderScheduling {
    /// Set from the launch arguments so a test can pick either outcome.
    let grantsPermission: Bool

    func apply(_ reminder: StudySettings.Reminder) async -> Bool {
        !reminder.isEnabled || grantsPermission
    }

    /// Environment variable UI tests set. An environment value is used rather than a launch
    /// argument because `UserDefaults` parses `-key value` pairs out of the argument list.
    static let environmentKey = "FLASHUP_UI_TEST_REMINDERS"

    /// Returns a stub when the process was launched by a UI test, and `nil` in production.
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StubReminderScheduler? {
        switch environment[environmentKey] {
        case "granted": StubReminderScheduler(grantsPermission: true)
        case "denied": StubReminderScheduler(grantsPermission: false)
        default: nil
        }
    }
}
