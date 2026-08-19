import Foundation

/// A deck of notes. Identity is the app-level `uuid` (spec §0.2) — never a store id.
public struct Deck: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    /// True for the bundled demo deck installed by onboarding.
    public var isDemo: Bool
    /// Stable seed identity/version used to upgrade demo content without touching user decks.
    public var demoSeedID: String?
    public var demoVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDemo: Bool = false,
        demoSeedID: String? = nil,
        demoVersion: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDemo = isDemo
        self.demoSeedID = demoSeedID
        self.demoVersion = demoVersion
    }
}
