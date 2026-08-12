import Foundation
import Testing
@testable import FlashUpData

/// Exercised against real `.apkg` files exported by Anki 26.08 — one per container
/// generation. See `Fixtures/make_fixtures.py` for how they are built.
@Suite("Anki .apkg reader")
struct ApkgReaderTests {
    // MARK: - Fixtures

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "apkg"),
            "missing fixture \(name).apkg"
        )
        return try Data(contentsOf: url)
    }

    static func collection(_ name: String) throws -> ApkgCollection {
        try ApkgArchive(data: fixture(name)).readCollection()
    }

    // MARK: - Container

    @Test("Both container generations yield the same eight notes", arguments: ["legacy", "modern"])
    func bothGenerationsRead(_ name: String) throws {
        let collection = try Self.collection(name)
        #expect(collection.notes.count == 8)
    }

    /// The regression that matters most. Every modern export still ships a `collection.anki2`
    /// holding one note that says "Please update to the latest Anki version…". A reader that
    /// takes the first collection it finds imports that note and drops the whole deck.
    @Test("The legacy collection.anki2 decoy is never the one read", arguments: ["legacy", "modern"])
    func decoyIsIgnored(_ name: String) throws {
        let collection = try Self.collection(name)
        let fronts = collection.notes.compactMap(\.fields.first)
        #expect(!fronts.contains { $0.contains("Please update to the latest Anki version") })
    }

    @Test("An archive with no collection database is refused")
    func noCollection() {
        // A valid but empty ZIP: end-of-central-directory record only.
        let emptyZip = Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
        #expect(throws: ApkgError.noCollection) {
            _ = try ApkgArchive(data: emptyZip)
        }
    }

    @Test("Something that is not a ZIP is refused")
    func notAZip() {
        #expect(throws: ApkgError.notAZipArchive) {
            _ = try ApkgArchive(data: Data("this is not a zip file at all".utf8))
        }
    }

    @Test("A file over the size cap is refused before anything is parsed")
    func fileTooLarge() throws {
        let limits = ApkgLimits(
            maxNotes: 10, maxFileBytes: 1024, maxExpandedBytes: 1 << 20,
            maxMediaCount: 10, maxMediaBytes: 1024
        )
        #expect(throws: ApkgError.self) {
            _ = try ApkgArchive(data: try Self.fixture("modern"), limits: limits)
        }
    }

    @Test("A collection with more notes than the cap is refused")
    func tooManyNotes() throws {
        let limits = ApkgLimits(
            maxNotes: 3, maxFileBytes: 1 << 30, maxExpandedBytes: 1 << 30,
            maxMediaCount: 100, maxMediaBytes: 1 << 20
        )
        #expect(throws: ApkgError.tooManyNotes(notes: 8, limit: 3)) {
            _ = try ApkgArchive(data: try Self.fixture("modern"), limits: limits).readCollection()
        }
    }

    @Test("An .apkg with no notes reads as an empty collection, not an error")
    func emptyCollection() throws {
        let collection = try Self.collection("empty")
        #expect(collection.notes.isEmpty)
        #expect(collection.usedNoteTypes.isEmpty)
    }

    // MARK: - Note types across both schemas

    /// Legacy carries schema 11 (note types as JSON in `col.models`), modern carries
    /// schema 18 (real `notetypes`/`fields`/`templates` tables). Both must produce the same
    /// answer, which is the whole reason both code paths exist.
    @Test("Note types read identically from schema 11 and schema 18", arguments: ["legacy", "modern"])
    func noteTypesMatchAcrossSchemas(_ name: String) throws {
        let collection = try Self.collection(name)
        let byName = Dictionary(uniqueKeysWithValues: collection.usedNoteTypes.map { ($0.name, $0) })

        let basic = try #require(byName["Basic"])
        #expect(basic.fieldNames == ["Front", "Back"])
        #expect(basic.isCloze == false)
        #expect(basic.templateCount == 1)

        let reversed = try #require(byName["Basic (and reversed card)"])
        #expect(reversed.templateCount == 2, "two templates is how Anki says 'and reversed card'")
        #expect(reversed.isCloze == false)

        let cloze = try #require(byName["Cloze"])
        #expect(cloze.isCloze, "notetype kind 1 means cloze")
        #expect(cloze.fieldNames == ["Text", "Back Extra"])

        let custom = try #require(byName["Cinque Campi"])
        #expect(custom.fieldNames == ["Termine", "Definizione", "Esempio", "Fonte", "Note"])
    }

    @Test("Only note types some note actually uses are offered", arguments: ["legacy", "modern"])
    func unusedNoteTypesAreDropped(_ name: String) throws {
        let collection = try Self.collection(name)
        #expect(collection.usedNoteTypes.count == 4)
        #expect(collection.noteTypes.count >= collection.usedNoteTypes.count)
    }

    // MARK: - Notes

    @Test("Fields are split on the unit separator, tags on whitespace", arguments: ["legacy", "modern"])
    func fieldsAndTags(_ name: String) throws {
        let collection = try Self.collection(name)
        let note = try #require(collection.notes.first { $0.fields.first?.hasPrefix("Qual è") == true })
        #expect(note.fields == ["Qual è la capitale d'Italia?", "Roma"])
        #expect(Set(note.tags) == ["geografia", "europa"])
    }

    @Test("A five-field note keeps all five fields", arguments: ["legacy", "modern"])
    func customNoteTypeFields(_ name: String) throws {
        let collection = try Self.collection(name)
        let note = try #require(collection.notes.first { $0.fields.first == "Entropia" })
        #expect(note.fields.count == 5)
        #expect(note.fields[3] == "Termodinamica, cap. 2")
    }

    @Test("Cloze syntax survives the reader untouched", arguments: ["legacy", "modern"])
    func clozeSyntaxIsPreserved(_ name: String) throws {
        let collection = try Self.collection(name)
        let note = try #require(collection.notes.first { $0.fields.first?.contains("glicolisi") == true })
        #expect(note.fields[0] == "La {{c1::glicolisi}} avviene nel {{c2::citoplasma}}")
    }

    @Test("Field HTML is delivered raw, for the domain layer to convert", arguments: ["legacy", "modern"])
    func htmlIsNotDecodedHere(_ name: String) throws {
        let collection = try Self.collection(name)
        let note = try #require(collection.notes.first { $0.fields.first?.contains("DNA") == true })
        #expect(note.fields[0].contains("<b>DNA</b>"))
        #expect(note.fields[0].contains("&amp;"))
    }

    @Test("Notes carry the name of the deck they came from", arguments: ["legacy", "modern"])
    func deckName(_ name: String) throws {
        let collection = try Self.collection(name)
        #expect(collection.notes.allSatisfy { $0.deckName == "Fixture Deck" })
    }

    // MARK: - Media

    @Test("Both the JSON and the protobuf media index resolve the same names",
          arguments: ["legacy", "modern"])
    func mediaIndex(_ name: String) throws {
        let archive = try ApkgArchive(data: Self.fixture(name))
        #expect(archive.mediaFilenames == ["rossa.png", "suono.wav"])
    }

    /// Legacy stores media blobs plain; modern stores each one zstd-compressed. The caller
    /// should not have to know which.
    @Test("Media bytes come back decompressed either way", arguments: ["legacy", "modern"])
    func mediaBytes(_ name: String) throws {
        let archive = try ApkgArchive(data: Self.fixture(name))

        let png = try archive.mediaData(named: "rossa.png")
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "PNG magic")

        let wav = try archive.mediaData(named: "suono.wav")
        #expect(wav.prefix(4) == Data("RIFF".utf8))
    }

    @Test("Asking for media that is not there is an error, not an empty result")
    func missingMedia() throws {
        let archive = try ApkgArchive(data: Self.fixture("modern"))
        #expect(throws: ApkgError.missingEntry(name: "nope.png")) {
            _ = try archive.mediaData(named: "nope.png")
        }
    }

    @Test("A media blob over the per-file cap is refused")
    func mediaTooLarge() throws {
        let limits = ApkgLimits(
            maxNotes: 100, maxFileBytes: 1 << 30, maxExpandedBytes: 1 << 30,
            maxMediaCount: 100, maxMediaBytes: 8
        )
        let archive = try ApkgArchive(data: Self.fixture("modern"), limits: limits)
        #expect(throws: ApkgError.self) {
            _ = try archive.mediaData(named: "rossa.png")
        }
    }
}

// MARK: - Zip bomb defence

@Suite("Decompression caps")
struct ApkgDecompressionTests {
    /// The shape the cap exists to stop: a frame of a few dozen bytes that declares a
    /// gigabyte of output. The declared size is checked *before* allocating.
    @Test("A zstd frame declaring more than the cap is refused before allocating")
    func zstdBombIsRefused() throws {
        // Frame header: magic, then a frame content size of 1 GiB.
        var frame = Data(ZstdDecoder.magic)
        frame.append(contentsOf: [0xE0])
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x40])
        #expect(throws: ApkgError.self) {
            _ = try ZstdDecoder.decompress(frame, limit: 1024, entry: "bomb")
        }
    }

    /// Anki writes the modern `media` index as a streaming frame with no declared content
    /// size, so "undeclared" cannot simply be refused — it has to stream, under the same cap.
    @Test("An undeclared frame streams, and a truncated one is still caught")
    func undeclaredSizeStreams() {
        let truncated = Data(ZstdDecoder.magic) + Data([0x00, 0x00, 0x00])
        #expect(throws: ApkgError.self) {
            _ = try ZstdDecoder.decompress(truncated, limit: 1 << 20, entry: "unsized")
        }
    }

    @Test("A streaming frame stops at the cap instead of exhausting memory")
    func streamingRespectsTheCap() throws {
        // The modern media index is exactly this shape: a real undeclared frame.
        let archive = try ApkgReaderTests.fixture("modern")
        let limits = ApkgLimits(
            maxNotes: 100, maxFileBytes: 1 << 30, maxExpandedBytes: 4,
            maxMediaCount: 100, maxMediaBytes: 1 << 20
        )
        #expect(throws: ApkgError.self) {
            _ = try ApkgArchive(data: archive, limits: limits)
        }
    }

    @Test("Bytes that are not a zstd frame are not mistaken for one")
    func magicDetection() {
        #expect(ZstdDecoder.isFrame(Data([0x28, 0xB5, 0x2F, 0xFD, 0x00])))
        #expect(!ZstdDecoder.isFrame(Data("{\"0\":\"a.png\"}".utf8)))
        #expect(!ZstdDecoder.isFrame(Data()))
    }
}
