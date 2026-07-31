import CryptoKit
import Foundation

/// Stable identifiers derived from content rather than allocated at random.
///
/// The recording pipeline reruns the same flows and expects the same frames; identifiers
/// that change per launch move rows, reorder queues and desynchronise an edit that was cut
/// against a previous take. Deriving them from the deck slug and the row's own content
/// makes a demo library reproducible across runs and across machines.
enum DeterministicID {
    /// Namespaced so two decks can carry identical rows without colliding.
    static func uuid(_ components: String...) -> UUID {
        var digest = SHA256()
        digest.update(data: Data("flashup-demo".utf8))
        for component in components {
            digest.update(data: Data([0x1F]))
            digest.update(data: Data(component.utf8))
        }

        var bytes = Array(digest.finalize().prefix(16))
        // RFC 4122 version 4 / variant bits, so the value is a well-formed UUID rather than
        // an arbitrary 128-bit number that happens to print like one.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
