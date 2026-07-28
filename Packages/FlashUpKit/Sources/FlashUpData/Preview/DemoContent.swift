import FlashUpDomain
import Foundation

/// Seed content for the in-memory repository.
///
/// It doubles as the shape of the bundled demo deck that onboarding installs, so the
/// interface is always designed against realistic Italian and English study material
/// rather than lorem ipsum.
public enum DemoContent {
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
