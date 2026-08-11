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
        let logger = Logger(subsystem: Self.loggingSubsystem, category: "app")
        self.logger = logger
        let demoModes = DemoMode.allFromEnvironment()
        self.library = library ?? demoModes.flatMap { Self.demoLibrary($0, logger: logger) } ?? InMemoryLibrary()
        // A recording session must never schedule a real notification: a banner dropping
        // into frame ruins a take that is otherwise finished (spec §3.1).
        let liveReminders: any ReminderScheduling = demoModes == nil
            ? ReminderScheduler()
            : StubReminderScheduler(grantsPermission: true)
        self.reminders = reminders ?? StubReminderScheduler.fromEnvironment() ?? liveReminders
    }

    /// The library the marketing pipeline records against.
    ///
    /// Reached only when `DEMO_MODE=1` was set, so the shipping path is untouched. When the
    /// deck cannot be loaded an empty library is returned rather than the ordinary demo
    /// seed: a flow must fail on its first assertion instead of quietly recording the wrong
    /// deck, which only becomes visible once the footage is on the timeline.
    private static func demoLibrary(_ modes: [DemoMode], logger: Logger) -> (any LibraryRepository)? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.fault("Demo mode requested but the Documents directory is unavailable")
            return nil
        }

        do {
            return try InMemoryLibrary.demo(modes, documents: documents)
        } catch {
            // Deck names are pipeline configuration, not card text, so logging the slug is
            // within the privacy rule that keeps user content out of diagnostics.
            let slugs = modes.map(\.slug).joined(separator: ",")
            logger.fault("Demo decks '\(slugs, privacy: .public)' failed to seed: \(error)")
            return nil
        }
    }
}
