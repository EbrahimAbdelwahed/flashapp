import Foundation

/// How the marketing pipeline asks the app for a known, reproducible library.
///
/// The pipeline copies a hand-authored deck into the app container and launches with
/// `DEMO_MODE=1 DEMO_DECK=<slug>`. The same file is then also the artifact the import flow
/// picks up on camera, so one CSV serves both roles and there is nothing to keep in sync.
///
/// Absent or malformed configuration returns `nil` and the app seeds normally: a recording
/// harness must never be able to degrade the shipping launch path.
public struct DemoMode: Equatable, Sendable {
    public static let modeKey = "DEMO_MODE"
    public static let deckKey = "DEMO_DECK"
    public static let deckNameKey = "DEMO_DECK_NAME"
    /// Comma-separated deck slugs for a library demo with more than one subject.
    /// Each slug resolves to `<Documents>/demo/<slug>.csv`.
    public static let decksKey = "DEMO_DECKS"

    /// Filename stem of the deck CSV. Constrained to a bare identifier so an environment
    /// variable can never point the loader outside the app container.
    public let slug: String

    /// What the deck is called on screen. Real course material, never `Deck 1` (spec §1.12).
    public let deckName: String

    public init(slug: String, deckName: String) {
        self.slug = slug
        self.deckName = deckName
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DemoMode? {
        guard environment[modeKey] == "1" else { return nil }
        guard let slug = environment[deckKey], isBareIdentifier(slug) else { return nil }

        let declared = environment[deckNameKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilWhenEmpty
        return DemoMode(slug: slug, deckName: declared ?? slug.capitalized)
    }

    /// Reads either a single named deck (the original recording contract) or a compact
    /// comma-separated list. A malformed list fails as a whole: a demo must never quietly
    /// omit one subject and leave the recording misleading.
    public static func allFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [DemoMode]? {
        guard environment[modeKey] == "1" else { return nil }

        guard let declared = environment[decksKey]?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
            declared.isEmpty == false
        else {
            return fromEnvironment(environment).map { [$0] }
        }

        guard Set(declared).count == declared.count else { return nil }
        let modes = declared.map { DemoMode(slug: String($0), deckName: String($0).capitalized) }
        guard modes.allSatisfy({ isBareIdentifier($0.slug) }) else { return nil }
        return modes
    }

    /// `<container>/Documents/demo/<slug>.csv` — where `scripts/seed.sh` drops the deck.
    public func csvURL(documents: URL) -> URL {
        documents
            .appendingPathComponent("demo", isDirectory: true)
            .appendingPathComponent("\(slug).csv")
    }

    private static let allowedSlugCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")

    private static func isBareIdentifier(_ value: String) -> Bool {
        guard value.isEmpty == false, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy(allowedSlugCharacters.contains)
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
