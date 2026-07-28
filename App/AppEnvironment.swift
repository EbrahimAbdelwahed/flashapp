import FlashUpData
import FlashUpDomain
import Observation
import OSLog
import SwiftUI

/// Composition root.
///
/// It owns the choice of repository implementation and nothing else knows which one is in
/// use. Today that is `InMemoryLibrary`, so the interface can be built and demonstrated
/// before the Core Data stack exists; `fu-04-data-core` swaps in the persistent one here,
/// and no view changes.
@Observable
@MainActor
final class AppEnvironment {
    /// Logger subsystem required by spec §0.2. Categories are added per subsystem.
    /// Logs carry metadata only — never card text.
    static let loggingSubsystem = "com.flashup.app"

    let logger: Logger
    let library: any LibraryRepository
    let reminders: any ReminderScheduling

    /// The chosen appearance lives here because two screens need it: Settings writes it and
    /// the root scene applies it. Holding it in either one alone means the other never hears
    /// about the change.
    var appearance: StudySettings.Appearance = .system

    /// What the root scene hands to `preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func loadAppearance() async {
        appearance = await library.settings().appearance
    }

    init(library: (any LibraryRepository)? = nil, reminders: (any ReminderScheduling)? = nil) {
        self.logger = Logger(subsystem: Self.loggingSubsystem, category: "app")
        self.library = library ?? InMemoryLibrary()
        self.reminders = reminders ?? StubReminderScheduler.fromEnvironment() ?? ReminderScheduler()
    }
}
