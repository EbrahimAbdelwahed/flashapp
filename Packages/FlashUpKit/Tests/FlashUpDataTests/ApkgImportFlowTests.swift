import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

/// The whole `.apkg` path over a real Anki export: archive → mapping → plan → commit → undo.
@Suite("Importing a real .apkg")
struct ApkgImportFlowTests {
    private func collection(_ name: String) throws -> ApkgCollection {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "apkg"))
        return try ApkgArchive(data: try Data(contentsOf: url)).readCollection()
    }

    private func defaultOutcome(_ name: String) throws -> CSVParseOutcome {
        let collection = try collection(name)
        let mappings = FieldMappingDefaults.propose(for: collection.noteTypeDescriptors())
        return ApkgRowMapper.map(notes: collection.sourceNotes(), mappings: mappings)
    }

    // MARK: - Proposed mapping

    @Test("The proposal reads each Anki note type correctly", arguments: ["legacy", "modern"])
    func proposedMappings(_ name: String) throws {
        let mappings = FieldMappingDefaults.propose(for: try collection(name).noteTypeDescriptors())
        let byName = Dictionary(uniqueKeysWithValues: mappings.map { ($0.noteTypeName, $0) })

        #expect(byName["Basic"]?.target == .basic)
        #expect(byName["Basic (and reversed card)"]?.target == .reversed)
        #expect(byName["Cloze"]?.target == .cloze)
        #expect(byName["Cinque Campi"]?.target == .basic)
        #expect(byName["Cinque Campi"]?.ignoredFieldNames == ["Esempio", "Fonte", "Note"])
    }

    @Test("Note counts per type are reported for the mapping screen", arguments: ["legacy", "modern"])
    func noteCounts(_ name: String) throws {
        let mappings = FieldMappingDefaults.propose(for: try collection(name).noteTypeDescriptors())
        let basic = try #require(mappings.first { $0.noteTypeName == "Basic" })
        #expect(basic.noteCount == 4, "four notes in the fixture use Basic")
    }

    // MARK: - Mapping to rows

    /// The fixture deliberately contains two notes our validation must refuse (a basic note
    /// with no back, a cloze with no deletion) and one that references media.
    @Test("Valid notes import and invalid ones are refused with a reason",
          arguments: ["legacy", "modern"])
    func outcome(_ name: String) throws {
        let outcome = try defaultOutcome(name)

        // Eight notes in: basic, reversed, cloze, five-field and an HTML-heavy basic map;
        // the media note, the backless basic and the deletion-less cloze are refused.
        #expect(outcome.rows.count == 5)
        #expect(outcome.rejected.count == 3)

        let reasons = outcome.rejected.map(\.reason)
        #expect(reasons.contains(.missingBack(.basic)))
        #expect(reasons.contains(.noClozeDeletion))
        #expect(reasons.contains(.unsupportedMedia("rossa.png")))
    }

    @Test("Both container generations produce identical rows")
    func generationsAgree() throws {
        let legacy = try defaultOutcome("legacy")
        let modern = try defaultOutcome("modern")
        #expect(legacy.rows == modern.rows)
        #expect(legacy.ignoredColumns == modern.ignoredColumns)
    }

    @Test("HTML in a field arrives as Flash Up text", arguments: ["legacy", "modern"])
    func htmlConverted(_ name: String) throws {
        let outcome = try defaultOutcome(name)
        let row = try #require(outcome.rows.first { $0.front.contains("DNA") })
        #expect(row.front == "Cos'è il **DNA**?\nDefinizione & struttura")
        #expect(row.back == "Acido desossiribonucleico\nDoppia elica\n— Watson & Crick")
    }

    @Test("A cloze note keeps both deletions", arguments: ["legacy", "modern"])
    func clozePreserved(_ name: String) throws {
        let outcome = try defaultOutcome(name)
        let row = try #require(outcome.rows.first { $0.type == .cloze })
        #expect(ClozeParser.groups(in: row.front) == [1, 2])
        #expect(row.back == "Prima tappa della respirazione cellulare")
    }

    @Test("Unused fields of the five-field note type are reported as ignored",
          arguments: ["legacy", "modern"])
    func ignoredColumns(_ name: String) throws {
        let outcome = try defaultOutcome(name)
        #expect(Set(outcome.ignoredColumns) == ["Esempio", "Fonte", "Note"])
    }

    @Test("Turning a note type off removes exactly its notes")
    func disablingANoteType() throws {
        let collection = try collection("modern")
        var mappings = FieldMappingDefaults.propose(for: collection.noteTypeDescriptors())
        let index = try #require(mappings.firstIndex { $0.noteTypeName == "Cinque Campi" })
        mappings[index].isEnabled = false

        let outcome = ApkgRowMapper.map(notes: collection.sourceNotes(), mappings: mappings)
        #expect(!outcome.rows.contains { $0.front == "Entropia" })
        #expect(outcome.rows.count == 4, "one fewer than the five that map by default")
    }

    @Test("Changing the front field changes what the card asks")
    func remappingFields() throws {
        let collection = try collection("modern")
        var mappings = FieldMappingDefaults.propose(for: collection.noteTypeDescriptors())
        let index = try #require(mappings.firstIndex { $0.noteTypeName == "Cinque Campi" })
        mappings[index].frontIndex = 1
        mappings[index].backIndex = 0

        let outcome = ApkgRowMapper.map(notes: collection.sourceNotes(), mappings: mappings)
        let row = try #require(outcome.rows.first { $0.back == "Entropia" })
        #expect(row.front == "Misura del disordine di un sistema")
    }

    // MARK: - Commit and undo, shared with the CSV importer

    /// The reason the mapper returns a `CSVParseOutcome`: everything below this line is the
    /// CSV importer's code, unchanged (ADR-004 §5).
    @Test("Importing creates notes, and undo sends them to the trash")
    func commitAndUndo() async throws {
        let library = InMemoryLibrary(seeded: false)
        let deck = await library.createDeck(named: "Anki")
        let plan = ImportPlanner.plan(try defaultOutcome("modern"), existingHashes: [:])

        let batch = await library.commitImport(
            plan, into: deck.id, sourceName: "modern.apkg", wasNewDeck: true
        )
        #expect(batch.createdNoteIDs.count == 5)

        var notes = await library.notes(in: deck.id, filters: SearchFilters(), now: Date())
        #expect(notes.count == 5)

        await library.undoImport(batch.id)
        notes = await library.notes(in: deck.id, filters: SearchFilters(), now: Date())
        #expect(notes.isEmpty, "undo sends imported notes to the trash, it does not destroy them")
    }

    @Test("A second import of the same file is flagged as duplicate")
    func reimportIsDuplicate() async throws {
        let library = InMemoryLibrary(seeded: false)
        let deck = await library.createDeck(named: "Anki")
        let outcome = try defaultOutcome("modern")

        _ = await library.commitImport(
            ImportPlanner.plan(outcome, existingHashes: [:]),
            into: deck.id, sourceName: "modern.apkg", wasNewDeck: true
        )

        let existing = await library.contentHashes(in: deck.id)
        let second = ImportPlanner.plan(outcome, existingHashes: existing)
        #expect(second.duplicates.count == 5)
        #expect(second.rowsToImport.isEmpty)
    }

    @Test("Cards are generated per type: reversed makes two, cloze one per deletion")
    func cardGeneration() async throws {
        let library = InMemoryLibrary(seeded: false)
        let deck = await library.createDeck(named: "Anki")
        let plan = ImportPlanner.plan(try defaultOutcome("modern"), existingHashes: [:])
        _ = await library.commitImport(plan, into: deck.id, sourceName: "m.apkg", wasNewDeck: true)

        // three basic notes (1 card each) + reversed (2) + cloze with two deletions (2) = 7
        let summaries = await library.decks()
        #expect(summaries.first { $0.deck.id == deck.id }?.totalCards == 7)
    }
}
