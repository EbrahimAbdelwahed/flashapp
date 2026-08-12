import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

@Suite("Media stores")
struct MediaStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("media-tests-\(UUID().uuidString)")
    }

    private func stores(_ directory: URL) -> [(String, any MediaStore)] {
        [("file", FileMediaStore(directory: directory)), ("memory", InMemoryMediaStore())]
    }

    @Test("Stored bytes come back unchanged")
    func roundTrip() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for (name, store) in stores(directory) {
            let bytes = Data("una immagine finta".utf8)
            let asset = try await store.store(bytes, filename: "foto.png", kind: .image)
            #expect(asset.kind == .image, "\(name)")
            #expect(asset.byteCount == bytes.count, "\(name)")
            #expect(await store.data(for: asset.id) == bytes, "\(name)")
            #expect(await store.asset(for: asset.id) == asset, "\(name)")
        }
    }

    /// Content addressing: the same picture in two decks must occupy one file.
    @Test("Storing identical bytes twice does not duplicate them")
    func deduplication() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for (name, store) in stores(directory) {
            let bytes = Data("stessi byte".utf8)
            let first = try await store.store(bytes, filename: "a.png", kind: .image)
            let second = try await store.store(bytes, filename: "b.png", kind: .image)
            #expect(first.id == second.id, "\(name): the same bytes are one asset")
            #expect(first.sha256 == second.sha256, "\(name)")
        }
    }

    @Test("Different bytes are different assets")
    func distinctAssets() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = InMemoryMediaStore()
        let first = try await store.store(Data("uno".utf8), filename: "a.png", kind: .image)
        let second = try await store.store(Data("due".utf8), filename: "b.png", kind: .image)
        #expect(first.id != second.id)
        #expect(await store.data(for: first.id) != (await store.data(for: second.id)))
    }

    @Test("Asking for an unknown id returns nothing rather than failing")
    func unknownID() async {
        let store = InMemoryMediaStore()
        #expect(await store.data(for: UUID()) == nil)
        #expect(await store.asset(for: UUID()) == nil)
    }

    @Test("A blob over the size cap is refused")
    func tooLarge() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileMediaStore(directory: directory, maxBytes: 8)
        await #expect(throws: MediaStoreError.self) {
            _ = try await store.store(Data(repeating: 0, count: 64), filename: "a.png", kind: .image)
        }
    }

    // MARK: - Garbage collection

    @Test("Sweeping removes only what nothing references")
    func sweep() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for (name, store) in stores(directory) {
            let kept = try await store.store(Data("tenere".utf8), filename: "a.png", kind: .image)
            let dropped = try await store.store(Data("buttare".utf8), filename: "b.png", kind: .image)

            await store.removeAll(except: [kept.id])

            #expect(await store.data(for: kept.id) != nil, "\(name): a referenced blob survives")
            #expect(await store.data(for: dropped.id) == nil, "\(name): an orphan is removed")
        }
    }

    /// The trap in content addressing: two assets can share one file, so dropping one of
    /// them must not delete the bytes the other still needs.
    @Test("Sweeping keeps a shared file that another asset still points at")
    func sweepRespectsSharedBlobs() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileMediaStore(directory: directory)
        let bytes = Data("condivisi".utf8)
        let asset = try await store.store(bytes, filename: "a.png", kind: .image)

        await store.removeAll(except: [asset.id])
        #expect(await store.data(for: asset.id) == bytes)
    }

    @Test("A file store reads back what a previous instance wrote")
    func persistsAcrossInstances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bytes = Data("persistente".utf8)
        let asset = try await FileMediaStore(directory: directory)
            .store(bytes, filename: "a.png", kind: .image)

        let reopened = FileMediaStore(directory: directory)
        #expect(await reopened.data(for: asset.id) == bytes)
        #expect(await reopened.url(for: asset.id) != nil)
    }

    @Test("Erasing everything leaves nothing behind")
    func removeAll() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileMediaStore(directory: directory)
        let asset = try await store.store(Data("x".utf8), filename: "a.png", kind: .image)
        await store.removeAll()
        #expect(await store.data(for: asset.id) == nil)
    }
}

@Suite("Backup format version 2")
struct BackupMediaTests {
    private func document(media: [MediaAsset], mediaIDs: [UUID]) -> BackupDocument {
        BackupDocument(
            appVersion: "1.0",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: .default,
            decks: [
                BackupDeck(
                    uuid: UUID(), name: "Mazzo", origin: .personal, createdAt: Date(timeIntervalSince1970: 0),
                    notes: [
                        BackupNote(
                            uuid: UUID(), type: .basic, front: "D", back: "R", tags: [],
                            createdAt: Date(timeIntervalSince1970: 0),
                            updatedAt: Date(timeIntervalSince1970: 0),
                            cards: [], mediaIDs: mediaIDs
                        )
                    ]
                )
            ],
            schedules: [], reviewLogs: [], media: media
        )
    }

    @Test("Attachment references survive an encode/decode round trip")
    func roundTrip() throws {
        let asset = MediaAsset(kind: .image, filename: "a.png", sha256: "abc", byteCount: 3)
        let original = document(media: [asset], mediaIDs: [asset.id])

        let decoded = try BackupCodec.decode(try BackupCodec.encode(original))
        #expect(decoded.media == [asset])
        #expect(decoded.decks.first?.notes.first?.mediaIDs == [asset.id])
        #expect(decoded.formatVersion == 2)
    }

    /// A version 1 backup predates attachments entirely and must still restore.
    @Test("A version 1 document still decodes, with no attachments")
    func version1StillDecodes() throws {
        let json = """
        {
          "format": "flashup-backup",
          "formatVersion": 1,
          "appVersion": "1.0",
          "exportedAt": "1970-01-01T00:00:00Z",
          "settings": \(String(data: try JSONEncoder().encode(StudySettings.default), encoding: .utf8) ?? "{}"),
          "decks": [],
          "schedules": [],
          "reviewLogs": []
        }
        """

        let decoded = try BackupCodec.decode(Data(json.utf8))
        #expect(decoded.media.isEmpty)
        #expect(decoded.formatVersion == 1)
    }

    @Test("The document reports which attachments its notes point at")
    func referencedIDs() {
        let asset = MediaAsset(kind: .audio, filename: "a.mp3", sha256: "abc", byteCount: 3)
        #expect(document(media: [], mediaIDs: [asset.id]).referencedMediaIDs == [asset.id])
    }
}
