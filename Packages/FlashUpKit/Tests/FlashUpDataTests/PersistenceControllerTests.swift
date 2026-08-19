import CoreData
import Foundation
import Testing
@testable import FlashUpData

@Suite("Versioned Core Data foundation", .serialized)
struct PersistenceControllerTests {
    @Test("The versioned model contains only the approved private entities")
    func modelIsCloudKitCompatible() throws {
        let model = try PersistenceController.loadModel()
        let bundledURL = try #require(PersistenceController.bundledModelURL)
        #expect(bundledURL.lastPathComponent == "FlashUpRuntime.momd")
        #expect(NSManagedObjectModel(contentsOf: bundledURL) != nil)
        #expect(model.versionIdentifiers.contains("V2"))
        #expect(CoreDataModelLint.issues(in: model).isEmpty)

        let names = Set(model.entities.compactMap(\.name))
        #expect(names == [
            "CDDeck", "CDNote", "CDCard", "CDTag", "CDSchedule", "CDReviewLog", "CDImportBatch", "CDStudySettings"
        ])
        #expect(names.contains("CDGroup") == false)
        #expect(names.contains("CDRevision") == false)
        #expect(names.contains("CDStudySession") == false)
        #expect(names.contains("CDOnboarding") == false)
        #expect(names.contains("CDNotificationAuthorization") == false)

        let settings = try #require(model.entitiesByName["CDStudySettings"])
        #expect(settings.attributesByName.keys.contains("singletonKey"))
        #expect(settings.attributesByName.keys.contains("newPerDay"))
        #expect(settings.attributesByName.keys.contains("reviewsPerDay"))
        #expect(settings.attributesByName.keys.contains("appearanceRaw"))
        #expect(settings.attributesByName.keys.contains("reminderEnabled"))
        #expect(settings.attributesByName.keys.contains("reminderHour"))
        #expect(settings.attributesByName.keys.contains("reminderMinute"))

        let expectedIndexes: [String: Set<String>] = [
            "CDDeck": ["uuidIndex", "deletedAtIndex"],
            "CDNote": ["uuidIndex", "deletedAtIndex"],
            "CDCard": ["uuidIndex", "deletedAtIndex"],
            "CDTag": ["uuidIndex", "normalizedNameIndex", "deletedAtIndex"],
            "CDSchedule": ["uuidIndex", "cardUUIDIndex", "deckUUIDIndex", "dueAtIndex"],
            "CDReviewLog": ["uuidIndex", "cardUUIDIndex", "deckUUIDIndex", "reviewedAtIndex"],
            "CDImportBatch": ["uuidIndex", "destinationDeckUUIDIndex", "importedAtIndex"],
            "CDStudySettings": ["uuidIndex", "singletonKeyIndex"]
        ]
        for (entityName, indexNames) in expectedIndexes {
            let entity = try #require(model.entitiesByName[entityName])
            let actualIndexNames = Set(entity.indexes.compactMap(\.name))
            #expect(indexNames.isSubset(of: actualIndexNames))
        }
    }

    @Test("An in-memory controller exposes history and remote-change options")
    func inMemoryOptions() throws {
        let controller = try PersistenceController(configuration: .inMemory)
        #expect(controller.storeDescription.type == NSInMemoryStoreType)
        #expect(controller.storeDescription.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
        #expect(
            controller.storeDescription.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber
                == true
        )
    }

    @Test("The private CloudKit description is configured without opening an account")
    func privateCloudKitDescription() throws {
        let url = temporaryStoreURL()
        let description = try PersistenceController.storeDescription(
            for: .cloudKit(storeURL: url, containerIdentifier: "iCloud.com.example.flashup")
        )
        let options = try #require(description.cloudKitContainerOptions)
        #expect(options.containerIdentifier == "iCloud.com.example.flashup")
        // `__databaseScope` is the SDK's refined Swift spelling for the Objective-C property.
        #expect(options.__databaseScope == 2)
        removeStoreFiles(at: url)
    }

    @Test("On-disk descriptions reject every non-Private.sqlite URL")
    func validatesStoreBasename() throws {
        let invalidURLs = [
            FileManager.default.temporaryDirectory.appendingPathComponent("FlashUp.sqlite"),
            FileManager.default.temporaryDirectory.appendingPathComponent("Private.sqlite.backup")
        ]
        for url in invalidURLs {
            #expect(throws: PersistenceError.self) {
                _ = try PersistenceController.storeDescription(for: .onDisk(storeURL: url))
            }
        }
    }

    @Test("On-disk data survives close and reopen")
    func onDiskReopen() throws {
        let url = temporaryStoreURL()
        defer { removeStoreFiles(at: url) }

        let identifier: UUID
        do {
            let controller = try PersistenceController(configuration: .onDisk(storeURL: url))
            let deck = try #require(
                NSEntityDescription.insertNewObject(forEntityName: "CDDeck", into: controller.viewContext)
                    as? CDDeck
            )
            deck.uuid = UUID()
            deck.name = "Relaunch proof"
            identifier = try #require(deck.uuid)
            try controller.save()
            try controller.close()
        }

        let reopened = try PersistenceController(configuration: .onDisk(storeURL: url))
        #expect(reopened.recoveryArtifact == nil)
        let request = CDDeck.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", identifier as CVarArg)
        let decks = try reopened.viewContext.fetch(request)
        #expect(decks.count == 1)
        #expect(decks.first?.name == "Relaunch proof")
        try reopened.close()
    }

    @Test("A corrupt store preserves original bytes and leaves a recovery artifact")
    func corruptStorePreservesOriginal() throws {
        let url = temporaryStoreURL()
        defer {
            removeStoreFiles(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
        }
        let original = Data("not a sqlite database".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: url)
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        let wal = Data("pending wal bytes".utf8)
        let shm = Data("shared memory bytes".utf8)
        try wal.write(to: walURL)
        try shm.write(to: shmURL)

        do {
            _ = try PersistenceController(configuration: .onDisk(storeURL: url))
            Issue.record("A corrupt SQLite store unexpectedly opened")
        } catch let error as PersistenceError {
            guard case let .storeLoadFailed(recoveryArtifact, _) = error else {
                Issue.record("Unexpected persistence error: \(error)")
                return
            }
            let artifact = try #require(recoveryArtifact)
            #expect(artifact.files.contains { $0.url.lastPathComponent == url.lastPathComponent })
            #expect(artifact.files.contains { $0.url.lastPathComponent == walURL.lastPathComponent })
            #expect(artifact.files.contains { $0.url.lastPathComponent == shmURL.lastPathComponent })
            #expect(try Data(contentsOf: url) == original)
            let preservedURL = artifact.directoryURL.appendingPathComponent(url.lastPathComponent)
            #expect(try Data(contentsOf: preservedURL) == original)
            #expect(try Data(contentsOf: artifact.directoryURL.appendingPathComponent(walURL.lastPathComponent)) == wal)
            #expect(try Data(contentsOf: artifact.directoryURL.appendingPathComponent(shmURL.lastPathComponent)) == shm)
        }
    }

}

extension PersistenceControllerTests {
    @Test("A migration-load failure preserves a valid prior store and sidecars")
    func migrationFailurePreservesPriorStore() throws {
        let url = temporaryStoreURL()
        let priorContainer = try makePriorStore(at: url)
        defer {
            for store in priorContainer.persistentStoreCoordinator.persistentStores {
                try? priorContainer.persistentStoreCoordinator.remove(store)
            }
            removeStoreFiles(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
        }

        let sourceURLs = storeURLs(at: url)
        #expect(sourceURLs.count == 3)
        let originalBytes = try self.originalBytes(for: sourceURLs)
        var loadedURLs: [URL] = []

        do {
            _ = try PersistenceController(
                configuration: .onDisk(storeURL: url),
                storeLoader: { container, completion in
                    if let loadedURL = container.persistentStoreDescriptions.first?.url {
                        loadedURLs.append(loadedURL)
                    }
                    completion(
                        container.persistentStoreDescriptions[0],
                        NSError(
                            domain: "FlashUpTests",
                            code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "injected migration failure"]
                        )
                    )
                }
            )
            Issue.record("An injected migration failure unexpectedly opened the store")
        } catch let error as PersistenceError {
            guard case let .storeLoadFailed(recoveryArtifact, reason) = error else {
                Issue.record("Unexpected persistence error: \(error)")
                return
            }
            #expect(reason == .migrationFailed)
            #expect(loadedURLs.count == 1)
            #expect(loadedURLs.first?.path.contains("/Staged/") == true)
            let artifact = try #require(recoveryArtifact)
            #expect(artifact.isValid())
            let stagedPath = artifact.directoryURL.appendingPathComponent("Staged").path
            #expect(FileManager.default.fileExists(atPath: stagedPath) == false)
            for sourceURL in sourceURLs {
                let original = try #require(originalBytes[sourceURL.lastPathComponent])
                #expect(try Data(contentsOf: sourceURL) == original)
                let preservedURL = artifact.directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                #expect(try Data(contentsOf: preservedURL) == original)
            }
        }
    }

    @Test("Recovery retains at most the two newest snapshots")
    func recoveryRetentionIsBounded() throws {
        let url = temporaryStoreURL()
        defer {
            removeStoreFiles(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        for value in 0..<3 {
            try Data("snapshot-\(value)".utf8).write(to: url)
            let artifact = try #require(try MigrationRecovery.preserveStoreFiles(at: url))
            #expect(artifact.isValid())
        }

        let recoveryRoot = url.deletingLastPathComponent().appendingPathComponent("Recovery")
        let directories = try FileManager.default.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        #expect(directories.count == 2)
    }

    @Test("A failed recovery copy removes its partial snapshot")
    func failedRecoveryRemovesPartialSnapshot() throws {
        let url = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        do {
            _ = try MigrationRecovery.preserveStoreFiles(at: url)
            Issue.record("A directory named Private.sqlite unexpectedly produced a snapshot")
        } catch let error as PersistenceError {
            #expect(error == .recoverySnapshotFailed)
        }

        let recoveryRoot = url.deletingLastPathComponent().appendingPathComponent("Recovery")
        let contents = try? FileManager.default.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        #expect(contents == nil || contents?.isEmpty == true)
    }

    @Test("A mutation during recovery copy rejects and removes the partial snapshot")
    func mutationDuringRecoveryCopyIsRejected() throws {
        let url = temporaryStoreURL()
        defer {
            removeStoreFiles(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("before mutation".utf8).write(to: url)
        var didMutate = false

        do {
            _ = try MigrationRecovery.preserveStoreFiles(
                at: url,
                fileManager: .default,
                copyHook: { event in
                    guard case let .afterCopy(sourceURL, _) = event, !didMutate else { return }
                    didMutate = true
                    try Data("during mutation".utf8).write(to: sourceURL)
                }
            )
            Issue.record("A source mutation during copy unexpectedly produced a recovery artifact")
        } catch let error as PersistenceError {
            #expect(error == .recoverySnapshotFailed)
        }
        #expect(didMutate)
        let recoveryRoot = url.deletingLastPathComponent().appendingPathComponent("Recovery")
        let contents = try? FileManager.default.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        #expect(contents?.isEmpty == true)
    }

    @Test("A scoped background task is released after completion")
    func scopedBackgroundTaskIsReleased() throws {
        let url = temporaryStoreURL()
        defer { removeStoreFiles(at: url) }
        let controller = try PersistenceController(configuration: .onDisk(storeURL: url))
        let identifier = try controller.performBackgroundTask { context in
            let deck = try #require(
                NSEntityDescription.insertNewObject(forEntityName: "CDDeck", into: context) as? CDDeck
            )
            deck.name = "Scoped background write"
            return try #require(deck.uuid)
        }
        #expect(controller.activeBackgroundOperationCount == 0)
        let request = CDDeck.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", identifier as CVarArg)
        #expect(try controller.viewContext.count(for: request) == 1)
        try controller.close()
    }

    @Test("Close waits for active background work and rejects new work")
    func closeWaitsForActiveBackgroundWork() throws {
        let url = temporaryStoreURL()
        defer { removeStoreFiles(at: url) }
        let controller = try PersistenceController(configuration: .onDisk(storeURL: url))
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? controller.performBackgroundTask { context in
                guard let deck = NSEntityDescription.insertNewObject(
                    forEntityName: "CDDeck",
                    into: context
                ) as? CDDeck else { return UUID() }
                deck.name = "Tracked background write"
                started.signal()
                release.wait()
                return deck.uuid
            }
        }
        #expect(started.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global().async {
            try? controller.close()
            closeFinished.signal()
        }
        while !controller.isClosingForTesting {
            Thread.sleep(forTimeInterval: 0.001)
        }
        #expect(controller.activeBackgroundOperationCount == 1)
        do {
            _ = try controller.performBackgroundTask { _ in true }
            Issue.record("Background work unexpectedly started after close began")
        } catch let error as PersistenceError {
            #expect(error == .backgroundWorkRejected)
        }
        #expect(closeFinished.wait(timeout: .now() + 0.1) == .timedOut)
        release.signal()
        #expect(closeFinished.wait(timeout: .now() + 3) == .success)
        #expect(controller.activeBackgroundOperationCount == 0)

        let reopened = try PersistenceController(configuration: .onDisk(storeURL: url))
        let request = CDDeck.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "Tracked background write")
        #expect(try reopened.viewContext.count(for: request) == 1)
        try reopened.close()
    }

    @Test("Public persistence errors do not expose framework paths or raw errors")
    func persistenceErrorsAreStable() {
        let error = PersistenceError.storeLoadFailed(recoveryArtifact: nil, reason: .migrationFailed)
        #expect(error.errorDescription == "The FlashApp store could not be opened. Existing data was preserved.")
        #expect(error.errorDescription?.contains("Private.sqlite") == false)
        #expect(error.errorDescription?.contains("NSSQLite") == false)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-persistence-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Private.sqlite")
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            let candidate = suffix.isEmpty ? url : URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.removeItem(at: candidate)
        }
    }

}
