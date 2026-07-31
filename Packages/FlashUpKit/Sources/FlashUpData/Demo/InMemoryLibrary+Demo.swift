import FlashUpDomain
import Foundation

public extension InMemoryLibrary {
    /// Builds the library the marketing pipeline records against.
    ///
    /// Throws rather than falling back: a flow recorded against a silently empty deck is a
    /// wasted take that only shows up once the footage is on the timeline.
    static func demo(
        _ mode: DemoMode,
        documents: URL,
        scheduler: FSRSService = SwiftFSRSAdapter(),
        now: Date = Date()
    ) throws -> InMemoryLibrary {
        let url = mode.csvURL(documents: documents)
        guard let csv = try? Data(contentsOf: url) else {
            throw DemoSeedError.fileUnreadable(path: url.path)
        }

        let store = try DemoDeckLoader.store(
            csv: csv,
            slug: mode.slug,
            deckName: mode.deckName,
            scheduler: scheduler,
            now: now
        )
        return InMemoryLibrary(scheduler: scheduler, store: store)
    }
}
