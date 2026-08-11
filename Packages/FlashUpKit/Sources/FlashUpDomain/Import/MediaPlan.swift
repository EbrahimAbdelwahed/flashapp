import Foundation

/// Which attachments an import can carry, and the identity each will get.
///
/// The mapper is pure and synchronous, but storing bytes is neither — and the store assigns
/// an id only once it has hashed the content. So the mapper emits **provisional** ids from
/// this plan, and the commit step rewrites them to the real ones after storing
/// (`MediaPlan.rewrite`). That keeps the whole mapping pass testable without a store.
public struct MediaPlan: Equatable, Sendable {
    private var provisional: [String: UUID]
    private var kinds: [String: MediaAsset.Kind]

    /// Empty: an import with no attachments available, which is every CSV import.
    public init() {
        provisional = [:]
        kinds = [:]
    }

    /// Assigns a provisional id to every filename Flash Up can carry. Anything else — video,
    /// documents — is deliberately absent, so a note referencing one is refused with a
    /// visible reason instead of importing with a hole in it.
    public init(availableFilenames: some Sequence<String>) {
        var provisional: [String: UUID] = [:]
        var kinds: [String: MediaAsset.Kind] = [:]
        for filename in availableFilenames {
            guard let kind = MediaAsset.Kind(filename: filename) else { continue }
            provisional[filename] = UUID()
            kinds[filename] = kind
        }
        self.provisional = provisional
        self.kinds = kinds
    }

    public var isEmpty: Bool { provisional.isEmpty }

    public func id(for filename: String) -> UUID? { provisional[filename] }
    public func kind(for filename: String) -> MediaAsset.Kind? { kinds[filename] }

    /// Filenames whose provisional id appears in `ids` — what the commit step actually has
    /// to extract and store. A deck's unused attachments are never touched.
    public func filenames(for ids: some Sequence<UUID>) -> [String] {
        let wanted = Set(ids)
        return provisional
            .filter { wanted.contains($0.value) }
            .map(\.key)
            .sorted()
    }

    /// Swaps provisional ids for the real ones the store handed back.
    ///
    /// Needed because the store deduplicates by content: importing a picture that is already
    /// on disk returns the id it already had, which is not the one the mapper guessed.
    public static func rewrite(_ text: String, replacing replacements: [UUID: UUID]) -> String {
        var result = text
        for (provisional, real) in replacements where provisional != real {
            result = result.replacingOccurrences(
                of: "\(MediaReference.scheme)://\(provisional.uuidString)",
                with: "\(MediaReference.scheme)://\(real.uuidString)"
            )
        }
        return result
    }
}
