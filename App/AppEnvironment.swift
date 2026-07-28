import FlashUpData
import FlashUpDomain
import Observation
import OSLog
import SwiftUI

/// Composition root.
///
/// Later beads build the persistence stack, the study engine and the sync services here
/// and inject them through the SwiftUI environment. At scaffold stage it only proves the
/// App -> FlashUpData -> FlashUpDomain link and owns the shared logger subsystem.
@Observable
final class AppEnvironment {
    /// Logger subsystem required by spec §0.2. Categories are added per subsystem.
    /// Logs carry metadata only — never card text.
    static let loggingSubsystem = "com.flashup.app"

    let logger: Logger

    /// Layers linked into the app target, used by the scaffold smoke checks.
    let linkedLayers: [String]

    init() {
        self.logger = Logger(subsystem: Self.loggingSubsystem, category: "app")
        self.linkedLayers = [FlashUpDomain.layerName, FlashUpData.layerName]
    }
}
