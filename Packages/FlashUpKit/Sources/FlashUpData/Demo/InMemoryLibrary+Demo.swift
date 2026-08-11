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
        try demo([mode], documents: documents, scheduler: scheduler, now: now)
    }

    /// Builds a multi-deck demo while keeping every deck on the same real CSV import path.
    static func demo(
        _ modes: [DemoMode],
        documents: URL,
        scheduler: FSRSService = SwiftFSRSAdapter(),
        now: Date = Date()
    ) throws -> InMemoryLibrary {
        let inputs = try modes.map { mode in
            let url = mode.csvURL(documents: documents)
            guard let csv = try? Data(contentsOf: url) else {
                throw DemoSeedError.fileUnreadable(path: url.path)
            }
            return DemoDeckInput(csv: csv, slug: mode.slug, deckName: mode.deckName)
        }

        let store = try DemoDeckLoader.store(
            inputs: inputs,
            scheduler: scheduler,
            now: now
        )
        return InMemoryLibrary(scheduler: scheduler, store: store)
    }
}
