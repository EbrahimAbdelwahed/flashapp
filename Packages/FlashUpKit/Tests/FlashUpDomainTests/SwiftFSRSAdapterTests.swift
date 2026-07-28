import Foundation
import Testing
@testable import FlashUpDomain

/// Bead fu-03 (source B0.4): proves the pinned engine is configurable, deterministic and
/// previewable before any schedule is persisted. See `docs/decisions/ADR-003-fsrs.md`.
@Suite("swift-fsrs adapter contract")
struct SwiftFSRSAdapterTests {
    /// A fixed instant so every expectation is reproducible on any machine and in any
    /// time zone.
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let service = SwiftFSRSAdapter()

    private func day(_ offset: Int) -> Date {
        Self.epoch.addingTimeInterval(Double(offset) * 86_400)
    }

    /// Folds a grade sequence, answering one card per day, exactly as
    /// `ScheduleReplayer` will (spec §A6.4).
    private func fold(_ grades: [Grade], using service: FSRSService) throws -> ReviewState {
        var state = ReviewState.unseen(dueAt: Self.epoch)
        for (index, grade) in grades.enumerated() {
            state = try service.next(state, grade: grade, at: day(index + 1)).updated
        }
        return state
    }

    @Test("Desired retention defaults to the 0.90 required by the brief")
    func desiredRetentionDefault() {
        #expect(service.desiredRetention == 0.90)
        #expect(SwiftFSRSAdapter.defaultDesiredRetention == 0.90)
    }

    @Test("Replaying the same grade sequence twice yields an identical state")
    func replayIsDeterministic() throws {
        let grades: [Grade] = [.good, .again, .hard, .good, .easy, .good]

        let first = try fold(grades, using: service)
        let second = try fold(grades, using: service)

        #expect(first == second)
    }

    @Test("A second adapter instance reproduces the first one's schedule")
    func replayIsStableAcrossInstances() throws {
        let grades: [Grade] = [.good, .good, .hard, .again, .good]

        let onDeviceA = try fold(grades, using: SwiftFSRSAdapter())
        let onDeviceB = try fold(grades, using: SwiftFSRSAdapter())

        #expect(onDeviceA == onDeviceB)
    }

    @Test("A first answer moves a card out of the new state and records the review")
    func firstAnswerLeavesTheNewState() throws {
        let transition = try service.next(.unseen(dueAt: Self.epoch), grade: .good, at: Self.epoch)

        #expect(transition.previous.state == .new)
        #expect(transition.updated.state != .new)
        #expect(transition.updated.reps == 1)
        #expect(transition.updated.lastReviewedAt == Self.epoch)
        #expect(transition.reviewedAt == Self.epoch)
        #expect(transition.elapsedDays == 0)
        #expect(transition.updated.dueAt > Self.epoch)
    }

    @Test("Answering Again on a review card counts a lapse and relearns it")
    func againCountsALapse() throws {
        let learned = try fold([.good, .good, .good], using: service)
        #expect(learned.state == .review)

        let lapsed = try service.next(learned, grade: .again, at: day(10)).updated

        #expect(lapsed.lapses == learned.lapses + 1)
        #expect(lapsed.state == .relearning)
    }

    @Test("Preview returns four outcomes ordered Again <= Hard <= Good <= Easy")
    func previewIsOrdered() throws {
        let state = try fold([.good, .good], using: service)
        let now = day(5)

        let preview = try service.preview(state, at: now)

        #expect(preview.interval(for: .again, from: now) <= preview.interval(for: .hard, from: now))
        #expect(preview.interval(for: .hard, from: now) <= preview.interval(for: .good, from: now))
        #expect(preview.interval(for: .good, from: now) <= preview.interval(for: .easy, from: now))
    }

    @Test("Preview does not commit: the same grade answered afterwards matches its preview")
    func previewMatchesTheCommittedAnswer() throws {
        let state = try fold([.good, .hard], using: service)
        let now = day(6)

        let preview = try service.preview(state, at: now)
        let committed = try service.next(state, grade: .good, at: now).updated

        #expect(preview[.good] == committed)
    }

    @Test("Preview is available for a card that has never been answered")
    func previewWorksForUnseenCards() throws {
        let preview = try service.preview(.unseen(dueAt: Self.epoch), at: Self.epoch)

        for grade in Grade.allCases {
            #expect(preview.interval(for: grade, from: Self.epoch) > 0)
        }
    }

    @Test("A lower desired retention schedules the card further out")
    func lowerRetentionMeansLongerIntervals() throws {
        let strict = SwiftFSRSAdapter(desiredRetention: 0.90)
        let relaxed = SwiftFSRSAdapter(desiredRetention: 0.70)

        let strictState = try fold([.good, .good], using: strict)
        let relaxedState = try fold([.good, .good], using: relaxed)

        #expect(relaxedState.dueAt > strictState.dueAt)
    }

    @Test("Grade and state raw values match the persisted contract")
    func rawValuesMatchThePersistedContract() {
        #expect(Grade.again.rawValue == 1)
        #expect(Grade.hard.rawValue == 2)
        #expect(Grade.good.rawValue == 3)
        #expect(Grade.easy.rawValue == 4)

        #expect(ScheduleState.new.rawValue == 0)
        #expect(ScheduleState.learning.rawValue == 1)
        #expect(ScheduleState.review.rawValue == 2)
        #expect(ScheduleState.relearning.rawValue == 3)
    }
}
