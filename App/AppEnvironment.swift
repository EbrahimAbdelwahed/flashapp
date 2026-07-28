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

    init(library: (any LibraryRepository)? = nil) {
        self.logger = Logger(subsystem: Self.loggingSubsystem, category: "app")
        self.library = library ?? InMemoryLibrary()
    }
}
