import FlashUpData
import FlashUpDomain
import Foundation
import Observation

/// Drives the import flow (spec §A9.2, §A9.5).
@Observable
@MainActor
final class ImportModel {
    enum Stage: Equatable {
        case choosing
        /// `.apkg` only. An Anki deck has its own note types and fields, and which field
        /// becomes the front is a decision only the user can make, so it is never silent.
        /// CSV goes straight from `.choosing` to `.preview`, exactly as before.
        case mapping
        case preview
        case done(Int)
    }

    enum Destination: Hashable {
        case newDeck
        case existing(UUID)
    }

    private let library: any LibraryRepository
    private let mediaStore: (any MediaStore)?

    private(set) var stage: Stage = .choosing
    private(set) var decks: [DeckSummary] = []
    private(set) var errorMessage: String?
    private(set) var lastBatchID: UUID?
    var plan = ImportPlan()
    var destination: Destination = .newDeck
    var newDeckName = ""
    var isPickingFile = false
    private var sourceName = ""

    /// One mapping per Anki note type, pre-filled with a proposal the user can change.
    var mappings: [FieldMapping] = []
    /// Whether the file in hand is an Anki deck. Only affects wording: a rejected `.apkg`
    /// entry is a note, not a line in a file, and pointing the user at "row 7" of a binary
    /// archive would be useless.
    private(set) var isApkg = false
    /// The Anki notes waiting for those mappings to be confirmed.
    private var sourceNotes: [SourceNote] = []
    /// Kept open until the import commits: attachment bytes are pulled out one at a time,
    /// so a deck with 200 MB of pictures is never resident all at once.
    private var archive: ApkgArchive?
    private var mediaPlan = MediaPlan()
    /// The parsed rows, kept so the plan can be rebuilt against a different deck: the user
    /// picks the destination on the preview screen, and duplicates are counted per deck.
    private var outcome: CSVParseOutcome?
    /// Attachments that could not be extracted. Their notes still import; the reference
    /// renders as a placeholder.
    private(set) var failedMediaCount = 0

    var canContinueFromMapping: Bool { mappings.contains(where: \.isEnabled) }

    init(library: any LibraryRepository, mediaStore: (any MediaStore)? = nil) {
        self.library = library
        self.mediaStore = mediaStore
    }

    func prepare() async {
        decks = await library.decks()
        if let first = decks.first, destination == .newDeck, newDeckName.isEmpty {
            // Importing into an existing deck is the common case once decks exist.
            destination = .existing(first.deck.id)
        }
    }

    func load(_ result: Result<URL, Error>) async {
        switch result {
        case let .success(url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = String(localized: "import.error.unreadable")
                return
            }
            // The extension is the only thing distinguishing the two formats here; an
            // `.apkg` is a ZIP, so sniffing bytes would just find "zip".
            if url.pathExtension.lowercased() == "apkg" {
                await loadApkg(data, sourceName: url.lastPathComponent)
            } else {
                await parse(data, sourceName: url.lastPathComponent)
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    /// CSV straight off the clipboard — the other half of the prompt card.
    ///
    /// An assistant answers with text, not with a file. Without this the shortest real journey
    /// (copy the prompt → ask ChatGPT → copy the answer) has to detour through saving a file
    /// and finding it again in the document picker, which is four system screens for a step the
    /// clipboard already did.
    ///
    /// The text arrives from a `PasteButton`: the user's tap on the system control *is* the
    /// authorization, so nothing here reads `UIPasteboard` behind their back and iOS never
    /// raises its "Allow Paste?" alert.
    func loadPasted(_ text: String) async {
        let csv = ImportModel.strippingCodeFence(text)
        guard csv.isEmpty == false else {
            errorMessage = String(localized: "import.error.empty_clipboard")
            return
        }
        await parse(Data(csv.utf8), sourceName: String(localized: "import.paste_name"))
    }

    /// Drops the ``` fences a chat interface wraps a code block in.
    ///
    /// The assistant is asked for a code block because that is the one thing with a copy
    /// button next to it. Copying with that button yields bare CSV, but selecting the block by
    /// hand takes the fences too, and a stray ```` ```csv ```` on line one would be read as the
    /// header row and fail the whole paste. The clipboard is a boundary, so it is cleaned here
    /// rather than in `CSVParser`, which stays strict about what a CSV file is.
    static func strippingCodeFence(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A built-in file so the flow can be tried (and tested) without a document picker.
    func loadSample() async {
        await parse(Data(ImportModel.sampleCSV.utf8), sourceName: String(localized: "import.sample_name"))
    }

    func commit() async {
        let deckID: UUID
        let wasNew: Bool
        switch destination {
        case .newDeck:
            let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
            let deck = await library.createDeck(named: name.isEmpty ? String(localized: "import.default_deck") : name)
            deckID = deck.id
            wasNew = true
        case let .existing(id):
            deckID = id
            wasNew = false
        }

        // Attachments first, then the notes: the store assigns the real ids, and the rows
        // still carry the provisional ones the mapper invented (ADR-004 §6).
        let committed = await storingMedia(plan)
        let batch = await library.commitImport(
            committed, into: deckID, sourceName: sourceName, wasNewDeck: wasNew
        )
        lastBatchID = batch.id
        stage = .done(batch.createdNoteIDs.count)
    }

    func undo() async {
        guard let lastBatchID else { return }
        await library.undoImport(lastBatchID)
        stage = .done(0)
    }

    // MARK: - Anki

    /// Opens the archive and stops at the mapping stage. Nothing is planned or written until
    /// the user has seen and accepted how the fields line up.
    func loadApkg(_ data: Data, sourceName: String) async {
        self.sourceName = sourceName
        isApkg = true

        do {
            // Parsing a large deck is real work, so it happens off the main actor — and the
            // archive is opened once and kept, not reopened for the attachments later.
            let opened = try await Task.detached(priority: .userInitiated) {
                let archive = try ApkgArchive(data: data)
                return (archive, try archive.readCollection())
            }.value
            let collection = opened.1

            guard !collection.notes.isEmpty else {
                errorMessage = String(localized: "import.error.apkg_empty")
                return
            }

            archive = opened.0
            // Only attachments Flash Up can carry get an id; a note referencing anything
            // else is refused in the preview, with the filename shown.
            mediaPlan = mediaStore == nil
                ? MediaPlan()
                : MediaPlan(availableFilenames: collection.mediaFilenames)
            sourceNotes = collection.sourceNotes()
            mappings = FieldMappingDefaults.propose(for: collection.noteTypeDescriptors())
            errorMessage = nil
            stage = .mapping
        } catch let error as ApkgError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = String(localized: "import.error.apkg_unreadable")
        }
    }

    /// Applies the confirmed mappings and moves to the shared preview. From here on the
    /// `.apkg` path is the CSV path (ADR-004 §5).
    func confirmMapping() async {
        outcome = ApkgRowMapper.map(notes: sourceNotes, mappings: mappings, media: mediaPlan)
        await replan()
        stage = .preview
    }

    /// Rebuilds the plan against the current destination. Called when the destination
    /// changes on the preview screen, so the duplicate count always describes the deck the
    /// notes are actually going into.
    func replan() async {
        guard let outcome else { return }
        plan = ImportPlanner.plan(outcome, existingHashes: await existingHashes())
    }

    /// Stores the attachments this import actually uses and rewrites the plan to point at
    /// them. A blob that cannot be extracted is counted and skipped, never fatal.
    private func storingMedia(_ plan: ImportPlan) async -> ImportPlan {
        guard let archive, let mediaStore, !mediaPlan.isEmpty else { return plan }

        let result = await ApkgMediaImporter.importMedia(
            for: plan.rowsToImport, from: archive, plan: mediaPlan, into: mediaStore
        )
        failedMediaCount = result.failedFilenames.count
        return plan.replacingMediaIDs(result.replacements)
    }

    /// The first note each mapping would produce, so the mapping screen can show the effect
    /// of a change instead of describing it.
    func previewRow(for mapping: FieldMapping) -> ParsedRow? {
        let notes = sourceNotes.filter { $0.noteTypeID == mapping.noteTypeID }
        var enabled = mapping
        enabled.isEnabled = true
        return ApkgRowMapper.map(notes: notes, mappings: [enabled], media: mediaPlan).rows.first
    }

    private func parse(_ data: Data, sourceName: String) async {
        self.sourceName = sourceName
        isApkg = false
        do {
            outcome = try CSVParser.parse(data)
            await replan()
            errorMessage = nil
            stage = .preview
        } catch let error as CSVParseError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = String(localized: "import.error.unreadable")
        }
    }

    /// Duplicates are only meaningful against a destination that already exists.
    private func existingHashes() async -> [UUID: String] {
        guard case let .existing(deckID) = destination else { return [:] }
        return await library.contentHashes(in: deckID)
    }

    /// Actionable, localized, and never a raw parser error (spec §0.2). The `.apkg` reader's
    /// structural failures are deliberately collapsed into a single suggestion the user can
    /// act on, rather than exposing ZIP and SQLite vocabulary.
    private static func message(for error: ApkgError) -> String {
        switch error {
        case let .fileTooLarge(_, limit):
            String(localized: "import.error.apkg_too_large \(limit / 1_048_576)")
        case let .expandedTooLarge(_, limit):
            String(localized: "import.error.apkg_too_large \(limit / 1_048_576)")
        case let .tooManyNotes(_, limit):
            String(localized: "import.error.apkg_too_many_notes \(limit)")
        case .noCollection, .notAZipArchive, .unsupportedZipFormat, .unsupportedCompression,
             .missingEntry, .corruptedData, .unsupportedSchema, .databaseUnreadable:
            String(localized: "import.error.apkg_unreadable")
        }
    }

    /// Actionable, localized, and never a raw parser error (spec §0.2).
    private static func message(for error: CSVParseError) -> String {
        switch error {
        case .notUTF8:
            String(localized: "import.error.encoding")
        case let .fileTooLarge(_, limit):
            String(localized: "import.error.too_large \(limit / 1_048_576)")
        case let .tooManyRows(_, limit):
            String(localized: "import.error.too_many_rows \(limit)")
        case .missingHeader:
            String(localized: "import.error.no_header")
        case let .missingColumns(missing, _):
            String(localized: "import.error.missing_columns \(missing.joined(separator: ", "))")
        }
    }

    static let sampleCSV = """
    type,front,back,tags
    basic,Qual è la funzione dei mitocondri?,Produzione di ATP,biologia
    reversed,Bone,Osso,english
    cloze,La glicolisi avviene nel {{c1::citoplasma}},,biologia
    basic,,Manca la domanda,scartata
    """
}
