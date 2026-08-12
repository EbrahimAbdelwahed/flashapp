import FlashUpDomain
import Foundation

/// Moves the attachments an import actually uses out of the archive and into the media store.
///
/// Only referenced files are touched: a deck can carry hundreds of megabytes of pictures for
/// notes the user chose not to import, and none of that should reach the disk. Each blob is
/// extracted, stored and released one at a time rather than held together in memory.
public enum ApkgMediaImporter {
    public struct Result: Sendable {
        /// Provisional id → the id the store actually assigned. Feed to
        /// `ParsedRow.replacingMediaIDs`.
        public let replacements: [UUID: UUID]
        /// Attachments that could not be extracted or stored. Their references stay in the
        /// text and render as a placeholder: a missing picture must not fail the import.
        public let failedFilenames: [String]

        public init(replacements: [UUID: UUID], failedFilenames: [String]) {
            self.replacements = replacements
            self.failedFilenames = failedFilenames
        }
    }

    /// Stores every attachment referenced by `rows`.
    public static func importMedia(
        for rows: [ParsedRow],
        from archive: ApkgArchive,
        plan: MediaPlan,
        into store: any MediaStore
    ) async -> Result {
        let referenced = rows.flatMap(\.mediaIDs)
        guard !referenced.isEmpty else { return Result(replacements: [:], failedFilenames: []) }

        var replacements: [UUID: UUID] = [:]
        var failed: [String] = []

        for filename in plan.filenames(for: referenced) {
            guard let provisional = plan.id(for: filename),
                  let kind = plan.kind(for: filename) else { continue }

            do {
                let bytes = try archive.mediaData(named: filename)
                let asset = try await store.store(bytes, filename: filename, kind: kind)
                replacements[provisional] = asset.id
            } catch {
                // Never fails the import: the note is still worth having without its picture.
                failed.append(filename)
            }
        }

        return Result(replacements: replacements, failedFilenames: failed)
    }
}
