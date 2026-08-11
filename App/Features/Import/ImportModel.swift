import FlashUpDomain
import Foundation
import Observation

/// Drives the import flow (spec §A9.2).
@Observable
@MainActor
final class ImportModel {
    enum Stage: Equatable {
        case choosing
        case preview
        case done(Int)
    }

    enum Destination: Hashable {
        case newDeck
        case existing(UUID)
    }

    private let library: any LibraryRepository

    private(set) var stage: Stage = .choosing
    private(set) var decks: [DeckSummary] = []
    private(set) var errorMessage: String?
    private(set) var lastBatchID: UUID?
    var plan = ImportPlan()
    var destination: Destination = .newDeck
    var newDeckName = ""
    var isPickingFile = false
    private var sourceName = ""

    init(library: any LibraryRepository) {
        self.library = library
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
            await parse(data, sourceName: url.lastPathComponent)
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

        let batch = await library.commitImport(plan, into: deckID, sourceName: sourceName, wasNewDeck: wasNew)
        lastBatchID = batch.id
        stage = .done(batch.createdNoteIDs.count)
    }

    func undo() async {
        guard let lastBatchID else { return }
        await library.undoImport(lastBatchID)
        stage = .done(0)
    }

    private func parse(_ data: Data, sourceName: String) async {
        self.sourceName = sourceName
        do {
            let outcome = try CSVParser.parse(data)
            let existing: [UUID: String]
            if case let .existing(deckID) = destination {
                existing = await library.contentHashes(in: deckID)
            } else {
                existing = [:]
            }
            plan = ImportPlanner.plan(outcome, existingHashes: existing)
            errorMessage = nil
            stage = .preview
        } catch let error as CSVParseError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = String(localized: "import.error.unreadable")
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
