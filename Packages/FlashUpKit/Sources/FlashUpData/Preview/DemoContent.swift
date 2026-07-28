import FlashUpDomain
import Foundation

/// Seed content for the in-memory repository.
///
/// It doubles as the shape of the bundled demo deck that onboarding installs, so the
/// interface is always designed against realistic Italian and English study material
/// rather than lorem ipsum.
public enum DemoContent {
    /// Builds a library that looks used: content, generated cards, and enough history that
    /// counters, streaks and the queue all have something real to show.
    static func seededStore(scheduler: FSRSService) -> LibraryStore {
        var store = LibraryStore()
        let decks = decks()
        for deck in decks { store.decks[deck.id] = deck }

        for note in notes(in: decks) {
            let draft = NoteDraft(
                id: note.id,
                deckID: note.deckID,
                type: note.type,
                front: note.front,
                back: note.back,
                tags: note.tags
            )
            _ = store.save(draft, now: note.createdAt)
        }

        seedHistory(into: &store, scheduler: scheduler, now: Date())
        return store
    }

    /// Answers roughly a third of the cards over the past few days, so streaks, retention
    /// and the due queue are exercised by the interface from the first launch.
    private static func seedHistory(into store: inout LibraryStore, scheduler: FSRSService, now: Date) {
        let grades: [Grade] = [.good, .easy, .hard, .good, .good, .again]
        let cards = store.cards.values.sorted { $0.id.uuidString < $1.id.uuidString }

        for (offset, card) in cards.enumerated() where offset % 3 == 0 {
            let answeredAt = now.addingTimeInterval(-Double((offset % 4) + 1) * 86_400)
            guard let transition = try? scheduler.next(
                .unseen(dueAt: answeredAt),
                grade: grades[offset % grades.count],
                at: answeredAt
            ) else { continue }
            store.record(transition, for: card.id, durationMs: 3_200)
        }
    }

    public static func decks() -> [Deck] {
        [
            Deck(name: "Anatomia — Sistema cardiovascolare", isDemo: true),
            Deck(name: "Farmacologia — Antibiotici"),
            Deck(name: "English — Medical terminology")
        ]
    }

    public static func notes(in decks: [Deck]) -> [Note] {
        guard decks.count >= 3 else { return [] }
        return anatomyNotes(deckID: decks[0].id)
            + pharmacologyNotes(deckID: decks[1].id)
            + englishNotes(deckID: decks[2].id)
    }

    private static func anatomyNotes(deckID anatomy: UUID) -> [Note] {
        [
            Note(
                deckID: anatomy,
                type: .cloze,
                front: "Il cuore è diviso in {{c1::quattro}} camere: due {{c2::atri}} e due {{c3::ventricoli}}.",
                back: "Il setto separa la parte destra dalla sinistra.",
                tags: ["anatomia", "cuore"]
            ),
            Note(
                deckID: anatomy,
                type: .basic,
                front: "Quale valvola separa l'atrio sinistro dal ventricolo sinistro?",
                back: "La valvola mitrale (bicuspide).",
                tags: ["anatomia", "valvole"]
            ),
            Note(
                deckID: anatomy,
                type: .basic,
                front: "Qual è la gittata cardiaca media a riposo?",
                back: "Circa 5 litri al minuto.",
                tags: ["fisiologia"]
            ),
            Note(
                deckID: anatomy,
                type: .cloze,
                front: "L'arteria {{c1::aorta}} nasce dal ventricolo {{c2::sinistro}}.",
                tags: ["anatomia"]
            )
        ]
    }

    private static func pharmacologyNotes(deckID pharma: UUID) -> [Note] {
        [
            Note(
                deckID: pharma,
                type: .basic,
                front: "Meccanismo d'azione delle penicilline",
                back: "Inibiscono la sintesi del peptidoglicano legandosi alle PBP.",
                tags: ["farmacologia", "antibiotici"]
            ),
            Note(
                deckID: pharma,
                type: .cloze,
                front: "I macrolidi inibiscono la subunità {{c1::50S}} del ribosoma batterico.",
                tags: ["farmacologia"]
            ),
            Note(
                deckID: pharma,
                type: .basic,
                front: "Principale effetto avverso degli aminoglicosidi",
                back: "Nefrotossicità e ototossicità.",
                tags: ["farmacologia"]
            )
        ]
    }

    private static func englishNotes(deckID english: UUID) -> [Note] {
        [
            Note(
                deckID: english,
                type: .reversed,
                front: "Shortness of breath",
                back: "Dispnea",
                tags: ["english"]
            ),
            Note(
                deckID: english,
                type: .reversed,
                front: "Bruise",
                back: "Ematoma / livido",
                tags: ["english"]
            ),
            Note(
                deckID: english,
                type: .basic,
                front: "What does 'NPO' mean on a chart?",
                back: "Nil per os — nothing by mouth.",
                tags: ["english", "abbreviations"]
            )
        ]
    }
}
