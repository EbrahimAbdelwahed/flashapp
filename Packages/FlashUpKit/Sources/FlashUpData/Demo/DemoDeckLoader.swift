import FlashUpDomain
import Foundation

/// Why a demo library could not be built. Every case is a loud failure: the pipeline must
/// stop rather than record a flow against an empty or half-seeded deck (spec §1.12, §3.2).
public enum DemoSeedError: Error, Equatable {
    case fileUnreadable(path: String)
    case noUsableRows(rejected: Int)
}

/// Turns a hand-authored deck CSV into a library that looks lived-in.
///
/// The CSV goes through the same parser the shipping import uses, so a deck that seeds
/// cleanly is by construction a deck the app can import on camera.
enum DemoDeckLoader {
    /// Review history is seeded across these consecutive past days, today included, so the
    /// streak counter has something believable to show without looking machine-perfect.
    private static let historyDays = 6

    /// A fixed hour of the day for every seeded answer: the date arithmetic stays stable
    /// regardless of when the recording session actually runs.
    private static let historyHour = 19

    /// A quarter of the deck is carried further back so those cards reach the multi-week
    /// intervals a real spaced-repetition deck shows. Without them every interval on screen
    /// reads "fra 1 giorno", which is what a deck created this morning looks like.
    private static let maturationDaysAgo = [26, 18, 12, 7]

    /// How far back the deck claims to have existed. Older than any seeded answer.
    private static let deckAgeDays = 34

    /// Every Nth card is never answered, so the deck keeps genuinely new cards.
    ///
    /// Without this the history is too thorough: six consecutive days of answering every
    /// third card covers all three residues, so no card survives unseen and the Nuove
    /// counter reads 0. A zero in frame is the empty state §1.12 forbids, and it also
    /// misrepresents the product — a deck you have entirely finished has nothing to
    /// demonstrate.
    private static let untouchedEveryNthCard = 5

    static func store(
        csv: Data,
        slug: String,
        deckName: String,
        scheduler: FSRSService,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> LibraryStore {
        let outcome = try CSVParser.parse(csv)
        guard outcome.rows.isEmpty == false else {
            throw DemoSeedError.noUsableRows(rejected: outcome.rejected.count)
        }

        var store = LibraryStore()
        let deck = Deck(
            id: DeterministicID.uuid("deck", slug),
            name: deckName,
            createdAt: now.addingTimeInterval(-Double(deckAgeDays) * 86_400),
            updatedAt: now,
            isDemo: true
        )
        store.decks[deck.id] = deck

        for row in outcome.rows {
            let draft = NoteDraft(
                id: DeterministicID.uuid("note", slug, String(row.line), row.front),
                deckID: deck.id,
                type: row.type,
                front: row.front,
                back: row.back,
                tags: row.tags
            )
            _ = store.save(draft, now: deck.createdAt)
        }

        stabiliseCardIdentity(in: &store, slug: slug)
        seedHistory(into: &store, scheduler: scheduler, now: now, calendar: calendar)
        return store
    }

    /// Replaces the random card identifiers the reconciler allocates with content-derived
    /// ones. Card identity is `(note, template key)` conceptually; making that literal is
    /// what lets two runs of the pipeline produce the same queue order.
    private static func stabiliseCardIdentity(in store: inout LibraryStore, slug: String) {
        store.cards.removeAll()

        for note in store.notes.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            for template in CardGenerator.generate(note) {
                let id = DeterministicID.uuid("card", slug, note.id.uuidString, template.templateKey)
                store.cards[id] = Card(id: id, noteID: note.id, deckID: note.deckID, template: template)
            }
        }
    }

    /// Answers a rotating third of the deck on each of the last few days, chaining each
    /// card's state through the real scheduler. The result is a genuine FSRS history —
    /// intervals on screen are computed, not written by hand.
    private static func seedHistory(
        into store: inout LibraryStore,
        scheduler: FSRSService,
        now: Date,
        calendar: Calendar
    ) {
        let grades: [Grade] = [.good, .easy, .good, .hard, .good, .easy]
        let all = store.cards.values.sorted { $0.id.uuidString < $1.id.uuidString }
        guard all.isEmpty == false else { return }

        let cards = all.enumerated()
            .filter { $0.offset % untouchedEveryNthCard != 0 }
            .map(\.element)

        // Mature the long-standing quarter of the deck first, so the recent streak below
        // lands on cards that already have a history rather than on a deck of new cards.
        for (step, daysAgo) in maturationDaysAgo.enumerated() {
            guard let answeredAt = answerTime(daysAgo: daysAgo, now: now, calendar: calendar) else { continue }

            for (index, card) in cards.enumerated() where index % 4 == 0 {
                let current = store.schedules[card.id] ?? .unseen(dueAt: answeredAt)
                guard let transition = try? scheduler.next(
                    current,
                    grade: step == 2 ? .easy : .good,
                    at: answeredAt
                ) else { continue }

                store.record(transition, for: card.id, durationMs: 2_100 + (index % 5) * 400)
            }
        }

        // Stops at yesterday, deliberately. Answering cards "today" consumes the daily
        // new-card allowance, and the app then shows a 0 in the Nuove counter — an empty
        // number in frame, which §1.12 rules out. A streak ending yesterday still counts
        // as unbroken, so nothing is lost. The demo library is a deck at the start of a
        // study day: work waiting, none of it done yet.
        for daysAgo in stride(from: historyDays, through: 1, by: -1) {
            guard let answeredAt = answerTime(daysAgo: daysAgo, now: now, calendar: calendar) else { continue }

            for (index, card) in cards.enumerated() where (index + daysAgo) % 3 == 0 {
                let current = store.schedules[card.id] ?? .unseen(dueAt: answeredAt)
                guard let transition = try? scheduler.next(
                    current,
                    grade: grades[(index + daysAgo) % grades.count],
                    at: answeredAt
                ) else { continue }

                store.record(transition, for: card.id, durationMs: 2_400 + (index % 6) * 500)
            }
        }
    }

    /// Never returns a time in the future: today's session is pinned to the evening hour
    /// like every other, unless the recording runs before it, in which case it lands just
    /// behind the present moment.
    private static func answerTime(daysAgo: Int, now: Date, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { return nil }
        guard let evening = calendar.date(bySettingHour: historyHour, minute: 12, second: 0, of: day) else {
            return nil
        }
        return min(evening, now.addingTimeInterval(-600))
    }
}
