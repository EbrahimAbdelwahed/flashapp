import FlashUpDomain
import Foundation

/// Namespace and build-shape marker for the persistence layer.
///
/// `FlashUpData` will own the Core Data stack and model, the repositories, sync,
/// sharing, purge and migration (bead `fu-04-data-core`). It depends on
/// `FlashUpDomain` and never the other way round (spec §0.3).
public enum FlashUpData {
    /// Layer identifier used by the scaffold smoke tests.
    public static let layerName = "FlashUpData"

    /// Proves the dependency direction App -> FlashUpData -> FlashUpDomain compiles.
    public static let domainLayerName = FlashUpDomain.layerName
}
