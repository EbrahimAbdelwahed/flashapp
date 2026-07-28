import Foundation

/// Namespace and build-shape marker for the pure domain layer.
///
/// `FlashUpDomain` holds portable logic only: cloze parsing, CSV codecs, the FSRS
/// wrapper, the study queue, metrics, deduplication and the backup codec.
/// It must never import UIKit, SwiftUI or Core Data (spec §0.3), and it must build
/// for macOS so its tests run without a simulator.
public enum FlashUpDomain {
    /// Layer identifier used by the scaffold smoke tests.
    public static let layerName = "FlashUpDomain"
}
