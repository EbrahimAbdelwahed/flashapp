import Foundation
import Testing
@testable import FlashUpData
@testable import FlashUpDomain

@Suite("Demo mode configuration")
struct DemoModeConfigurationTests {
    @Test("Absent DEMO_MODE means production seeding")
    func absentFlagMeansProduction() {
        #expect(DemoMode.fromEnvironment([:]) == nil)
        #expect(DemoMode.fromEnvironment(["DEMO_DECK": "anatomia"]) == nil)
        #expect(DemoMode.fromEnvironment(["DEMO_MODE": "0", "DEMO_DECK": "anatomia"]) == nil)
    }

    @Test("DEMO_MODE=1 without a deck is a configuration error, not a silent fallback")
    func flagWithoutDeckIsNil() {
        #expect(DemoMode.fromEnvironment(["DEMO_MODE": "1"]) == nil)
    }

    @Test("The deck slug and its display name come from the environment")
    func readsSlugAndName() throws {
        let mode = try #require(DemoMode.fromEnvironment([
            "DEMO_MODE": "1",
            "DEMO_DECK": "anatomia",
            "DEMO_DECK_NAME": "Anatomia — splancnologia"
        ]))
        #expect(mode.slug == "anatomia")
        #expect(mode.deckName == "Anatomia — splancnologia")
    }

    @Test("A missing display name falls back to the capitalised slug")
    func fallsBackToSlug() throws {
        let mode = try #require(DemoMode.fromEnvironment(["DEMO_MODE": "1", "DEMO_DECK": "biochimica"]))
        #expect(mode.deckName == "Biochimica")
    }

    @Test("A slug that is not a bare identifier is refused")
    func refusesPathTraversal() {
        #expect(DemoMode.fromEnvironment(["DEMO_MODE": "1", "DEMO_DECK": "../../etc/passwd"]) == nil)
        #expect(DemoMode.fromEnvironment(["DEMO_MODE": "1", "DEMO_DECK": "a/b"]) == nil)
        #expect(DemoMode.fromEnvironment(["DEMO_MODE": "1", "DEMO_DECK": ""]) == nil)
    }

    @Test("The CSV is looked for in the Documents demo folder the pipeline writes to")
    func resolvesCSVLocation() throws {
        let mode = try #require(DemoMode.fromEnvironment(["DEMO_MODE": "1", "DEMO_DECK": "anatomia"]))
        let root = URL(fileURLWithPath: "/tmp/container", isDirectory: true)
        #expect(mode.csvURL(documents: root).path == "/tmp/container/demo/anatomia.csv")
    }

    @Test("A comma-separated deck list creates distinct demo deck configurations")
    func readsMultipleDecks() throws {
        let modes = try #require(DemoMode.allFromEnvironment([
            "DEMO_MODE": "1",
            "DEMO_DECKS": "istologia,biochimica"
        ]))

        #expect(modes.map(\.slug) == ["istologia", "biochimica"])
        #expect(modes.map(\.deckName) == ["Istologia", "Biochimica"])
    }
}

@Suite("Demo deck loading")
struct DemoDeckLoaderTests {
    /// Eight notes: four basic, three cloze with two deletions each, one reversed.
    /// 4 + 6 + 2 = 12 cards, so the count also proves cloze and reversed generation.
    /// One field carries a quoted comma, which is the shape the shipped decks use.
    private static let csv = """
    type,front,back,tags
    basic,Quale foglietto riveste i visceri addominali?,Il peritoneo viscerale.,anatomia;peritoneo
    basic,Dove si trova la flessura splenica del colon?,Nell'ipocondrio sinistro.,anatomia;colon
    cloze,Lo stomaco è diviso in {{c1::fondo}} e {{c2::corpo}}.,,anatomia;stomaco
    basic,Che cosa secernono le cellule parietali?,Acido cloridrico e fattore intrinseco.,anatomia;stomaco
    cloze,Il dotto {{c1::coledoco}} sbocca nella {{c2::papilla di Vater}}.,,anatomia;fegato
    basic,Quanti lobi ha il polmone destro?,"Tre: superiore, medio e inferiore.",anatomia;polmoni
    cloze,Il rene è avvolto dalla capsula {{c1::fibrosa}} e dalla fascia {{c2::di Gerota}}.,,anatomia;rene
    reversed,Milza,Organo linfoide dell'ipocondrio sinistro.,anatomia;milza
    """

    private func load(now: Date = Date(timeIntervalSince1970: 1_780_000_000)) throws -> LibraryStore {
        try DemoDeckLoader.store(
            csv: Data(Self.csv.utf8),
            slug: "anatomia",
            deckName: "Anatomia — splancnologia",
            scheduler: SwiftFSRSAdapter(),
            now: now
        )
    }

    @Test("The deck carries the display name from the environment, not the slug")
    func deckIsNamed() throws {
        let store = try load()
        let deck = try #require(store.liveDecks.first)
        #expect(store.liveDecks.count == 1)
        #expect(deck.name == "Anatomia — splancnologia")
    }

    @Test("Every valid row becomes a note and cloze rows generate one card per deletion")
    func generatesCards() throws {
        let store = try load()
        #expect(store.liveNotes().count == 8)
        // 4 basic + 1 reversed (2 cards) + 3 cloze with 2 deletions each = 12 cards.
        #expect(store.cards.count == 12)
    }

    @Test("No shot can land on an empty state: the deck always has content")
    func neverEmpty() throws {
        let store = try load()
        #expect(store.cards.isEmpty == false)
        #expect(store.liveNotes().allSatisfy { $0.front.isEmpty == false })
    }

    @Test("Two loads of the same CSV produce byte-identical identity and scheduling")
    func isDeterministic() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let first = try load(now: now)
        let second = try load(now: now)

        #expect(first.decks.keys.sorted { $0.uuidString < $1.uuidString }
            == second.decks.keys.sorted { $0.uuidString < $1.uuidString })
        #expect(first.notes.keys.sorted { $0.uuidString < $1.uuidString }
            == second.notes.keys.sorted { $0.uuidString < $1.uuidString })
        #expect(first.cards.keys.sorted { $0.uuidString < $1.uuidString }
            == second.cards.keys.sorted { $0.uuidString < $1.uuidString })

        for (id, state) in first.schedules {
            #expect(second.schedules[id]?.dueAt == state.dueAt)
        }
    }

    @Test("A different slug produces different identifiers, so decks never collide")
    func slugScopesIdentity() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let anatomy = try load(now: now)
        let biochemistry = try DemoDeckLoader.store(
            csv: Data(Self.csv.utf8),
            slug: "biochimica",
            deckName: "Biochimica — ciclo di Krebs",
            scheduler: SwiftFSRSAdapter(),
            now: now
        )
        #expect(Set(anatomy.notes.keys).isDisjoint(with: Set(biochemistry.notes.keys)))
    }

    @Test("Multiple demo sources retain separate decks and varied FSRS states")
    func loadsMultipleDecksWithVariedSchedules() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = try DemoDeckLoader.store(
            inputs: [
                DemoDeckInput(csv: Data(Self.csv.utf8), slug: "istologia", deckName: "Istologia"),
                DemoDeckInput(csv: Data(Self.csv.utf8), slug: "biochimica", deckName: "Biochimica")
            ],
            scheduler: SwiftFSRSAdapter(),
            now: now
        )

        #expect(store.liveDecks.count == 2)
        #expect(store.liveNotes().count == 16)
        #expect(store.cards.count == 24)
        #expect(store.schedules.count > 0)
        #expect(store.schedules.count < store.cards.count)
        #expect(Set(store.schedules.values.map(\.dueAt)).count > 1)
    }

    @Test("Seeded history gives the interface a streak and a due queue to show")
    func seedsPlausibleHistory() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = try load(now: now)
        let metrics = MetricsCalculator.metrics(logs: store.logs, now: now)

        #expect(store.logs.isEmpty == false)
        #expect(metrics.streakDays >= 3)
        // A perfect streak reads as fake; §1.12 wants a believable one.
        #expect(metrics.streakDays <= 12)
        #expect(store.candidates(in: .allDecks).isEmpty == false)
    }

    /// Guards the counter, not the loader. The first seeding answered every card, which
    /// left the Nuove tile reading 0 on camera — the empty state §1.12 rules out.
    @Test("The deck keeps unseen cards, so the new-card counter is never zero")
    func keepsNewCards() throws {
        let store = try load()
        let unseen = store.cards.keys.filter { store.schedules[$0] == nil }
        #expect(unseen.isEmpty == false)
        // Some history too, or the deck reads as untouched rather than lived-in.
        #expect(unseen.count < store.cards.count)
    }

    @Test("At least one card is scheduled far enough out to show a real interval")
    func showsRealIntervals() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = try load(now: now)
        let furthest = store.schedules.values.map(\.dueAt).max()
        let due = try #require(furthest)
        #expect(due.timeIntervalSince(now) > 3 * 86_400)
    }

    /// Guards the hand-authored deck itself, not the loader. A typo that silently drops a
    /// row would otherwise only surface as a wrong card count on camera.
    @Test("The shipped anatomia deck parses cleanly and holds the intended card count")
    func shippedDeckIsIntact() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FlashUpDataTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FlashUpKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
        let deck = repository
            // The marketing pipeline moved under DEPRECATED/ when the app was restyled; the
            // deck itself is still the one the demo seeds from.
            .appendingPathComponent("DEPRECATED/marketing-pipeline/assets/decks/anatomia.csv")

        let csv = try Data(contentsOf: deck)
        let outcome = try CSVParser.parse(csv)
        #expect(outcome.rejected.isEmpty)
        #expect(outcome.rows.count == 32)

        let store = try DemoDeckLoader.store(
            csv: csv,
            slug: "anatomia",
            deckName: "Anatomia — splancnologia",
            scheduler: SwiftFSRSAdapter(),
            now: Date(timeIntervalSince1970: 1_780_000_000)
        )
        #expect(store.cards.count == 47)
        #expect(store.liveNotes().allSatisfy { $0.tags.isEmpty == false })
    }

    @Test("A CSV the parser rejects outright fails loudly instead of seeding an empty deck")
    func refusesUnusableCSV() {
        #expect(throws: (any Error).self) {
            try DemoDeckLoader.store(
                csv: Data("nothing,useful\n1,2".utf8),
                slug: "anatomia",
                deckName: "Anatomia",
                scheduler: SwiftFSRSAdapter(),
                now: Date()
            )
        }
    }
}
