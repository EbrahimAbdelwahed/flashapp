import Foundation

/// The four answers a learner can give to a card.
///
/// Raw values are persisted in `CDReviewLog.gradeRaw` and are deliberately identical to
/// the swift-fsrs `Rating` raw values, so the stored history keeps its meaning even if the
/// adapter is ever replaced. See `docs/decisions/ADR-003-fsrs.md`.
public enum Grade: Int16, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}
