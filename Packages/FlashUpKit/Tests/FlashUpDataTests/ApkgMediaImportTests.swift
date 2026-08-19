import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

/// Attachments, end to end: archive → mapped rows → stored blobs → notes that point at them.
@Suite("Importing .apkg attachments")
struct ApkgMediaImportTests {
    private func archive(_ name: String) throws -> ApkgArchive {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "apkg"))
        return try ApkgArchive(data: try Data(contentsOf: url))
    }

    /// Everything one fixture yields, ready to import.
    private struct Mapped {
        let archive: ApkgArchive
        let plan: MediaPlan
        let outcome: CSVParseOutcome
    }

    private func mapped(_ name: String) throws -> Mapped {
        let archive = try archive(name)
        let collection = try archive.readCollection()
        let plan = MediaPlan(availableFilenames: collection.mediaFilenames)
        return Mapped(
            archive: archive,
            plan: plan,
            outcome: ApkgRowMapper.map(
                notes: collection.sourceNotes(),
                mappings: FieldMappingDefaults.propose(for: collection.noteTypeDescriptors()),
                media: plan
            )
        )
    }

    /// Without a media plan the note is refused; with one it imports. That difference is the
    /// whole feature.
    @Test("With attachments available, the media note is no longer refused",
          arguments: ["legacy", "modern"])
    func mediaNoteImports(_ name: String) throws {
        let outcome = try mapped(name).outcome

        #expect(outcome.rows.count == 6, "the five text notes plus the one carrying media")
        #expect(!outcome.rejected.contains { $0.reason == .unsupportedMedia("rossa.png") })

        let row = try #require(outcome.rows.first { $0.front.contains("Che colore") })
        #expect(row.mediaIDs.count == 2, "one image on the front, one sound on the back")
        #expect(MediaReference.ids(in: row.front).count == 1)
        #expect(MediaReference.ids(in: row.back ?? "").count == 1)
    }

    @Test("The words survive alongside the attachment", arguments: ["legacy", "modern"])
    func textIsKept(_ name: String) throws {
        let outcome = try mapped(name).outcome
        let row = try #require(outcome.rows.first { $0.front.contains("Che colore") })
        #expect(MediaReference.stripping(row.front) == "Che colore è questo?")
        #expect(MediaReference.stripping(row.back ?? "") == "Rosso")
    }

    @Test("Storing the attachments swaps provisional ids for the real ones")
    func storeAndRewrite() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()
        let importPlan = ImportPlanner.plan(outcome, existingHashes: [:])

        let result = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )
        #expect(result.failedFilenames.isEmpty)
        #expect(result.replacements.count == 2)

        let rewritten = importPlan.replacingMediaIDs(result.replacements)
        let row = try #require(rewritten.rowsToImport.first { $0.front.contains("Che colore") })

        // Every id in the text now resolves to something the store actually holds.
        for id in row.mediaIDs {
            #expect(try await store.data(for: id) != nil)
        }
        #expect(MediaReference.ids(in: row.front) == [row.mediaIDs[0]])
    }

    @Test("The stored bytes are the real picture and the real sound")
    func storedBytesAreCorrect() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()
        let importPlan = ImportPlanner.plan(outcome, existingHashes: [:])
        let result = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )

        var kinds: [MediaAsset.Kind: Data] = [:]
        for id in result.replacements.values {
            let asset = try #require(try await store.asset(for: id))
            kinds[asset.kind] = try await store.data(for: id)
        }

        #expect(kinds[.image]?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "PNG magic")
        #expect(kinds[.audio]?.prefix(4) == Data("RIFF".utf8))
    }

    /// Only what the import needs: a deck's unused attachments must never reach the disk.
    @Test("Attachments belonging to skipped notes are not stored")
    func unusedAttachmentsAreNotStored() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()

        // No rows at all: nothing to attach.
        let result = await ApkgMediaImporter.importMedia(
            for: [], from: archive, plan: plan, into: store
        )
        #expect(result.replacements.isEmpty)
        #expect(outcome.rows.count == 6, "the rows still mapped; they were simply not committed")
    }

    @Test("Importing the same deck twice reuses one copy of each attachment")
    func reimportDeduplicates() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()
        let importPlan = ImportPlanner.plan(outcome, existingHashes: [:])

        let first = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )
        let second = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )

        #expect(Set(first.replacements.values) == Set(second.replacements.values),
                "the same bytes resolve to the same assets, not to new copies")
    }

    // MARK: - The whole way through the library

    @Test("An imported note carries its attachments, and undo keeps the blobs")
    func commitAndUndo() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()
        let library = InMemoryLibrary(seeded: false)
        let deck = await library.createDeck(named: "Anki")

        let importPlan = ImportPlanner.plan(outcome, existingHashes: [:])
        let result = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )
        let batch = await library.commitImport(
            importPlan.replacingMediaIDs(result.replacements),
            into: deck.id, sourceName: "modern.apkg", wasNewDeck: true
        )
        #expect(batch.createdNoteIDs.count == 6)

        let notes = await library.notes(in: deck.id, filters: SearchFilters(), now: Date())
        let withMedia = notes.filter { !$0.note.mediaIDs.isEmpty }
        #expect(withMedia.count == 1)
        #expect(withMedia.first?.note.mediaIDs.count == 2)

        // Undo soft-deletes the notes, so the blobs must stay: the notes can come back, and
        // `AGENTS.md` forbids destroying user data to tidy up (ADR-004 §6).
        await library.undoImport(batch.id)
        for id in withMedia.first?.note.mediaIDs ?? [] {
            #expect(try await store.data(for: id) != nil, "undo must not delete attachment bytes")
        }
    }

    @Test("Cards generated from a media note keep the reference in their faces")
    func cardsCarryReferences() async throws {
        let fixture = try mapped("modern")
        let (archive, plan, outcome) = (fixture.archive, fixture.plan, fixture.outcome)
        let store = InMemoryMediaStore()
        let library = InMemoryLibrary(seeded: false)
        let deck = await library.createDeck(named: "Anki")

        let importPlan = ImportPlanner.plan(outcome, existingHashes: [:])
        let result = await ApkgMediaImporter.importMedia(
            for: importPlan.rowsToImport, from: archive, plan: plan, into: store
        )
        _ = await library.commitImport(
            importPlan.replacingMediaIDs(result.replacements),
            into: deck.id, sourceName: "m.apkg", wasNewDeck: true
        )

        let notes = await library.notes(in: deck.id, filters: SearchFilters(), now: Date())
        let note = try #require(notes.first { !$0.note.mediaIDs.isEmpty })
        let cards = await library.cards(for: note.note.id)
        let card = try #require(cards.first)

        #expect(!MediaReference.ids(in: card.front).isEmpty)
        #expect(MediaReference.stripping(card.front) == "Che colore è questo?")
    }
}
