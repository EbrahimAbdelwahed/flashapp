import CoreData
import Foundation
import Testing
@testable import FlashUpData

extension PersistenceControllerTests {
    @Test("A successful staged migration adopts data and removes staging")
    func successfulStagedMigrationAdoptsData() throws {
        let url = temporaryMigrationStoreURL()
        let prior = try makePriorDeckStore(at: url)
        let identifier = prior.uuid
        try closeFixture(prior.container)
        defer { removeMigrationStoreFiles(at: url) }

        let controller = try PersistenceController(configuration: .onDisk(storeURL: url))
        let artifact = try #require(controller.recoveryArtifact)
        #expect(artifact.isValid())
        let stagedPath = artifact.directoryURL.appendingPathComponent("Staged").path
        #expect(FileManager.default.fileExists(atPath: stagedPath) == false)
        #expect(
            MigrationRecovery.preflight(at: url, model: try PersistenceController.loadModel()) == .compatible
        )

        let request = CDDeck.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", identifier as CVarArg)
        let deck = try #require(try controller.viewContext.fetch(request).first)
        #expect(deck.uuid == identifier)
        #expect(deck.name == "Migrated deck")
        try controller.close()

        let reopened = try PersistenceController(configuration: .onDisk(storeURL: url))
        #expect(reopened.recoveryArtifact == nil)
        #expect(
            MigrationRecovery.preflight(at: url, model: try PersistenceController.loadModel()) == .compatible
        )
        let reopenedRequest = CDDeck.fetchRequest()
        reopenedRequest.predicate = NSPredicate(format: "uuid == %@", identifier as CVarArg)
        let reopenedDeck = try #require(try reopened.viewContext.fetch(reopenedRequest).first)
        #expect(reopenedDeck.uuid == identifier)
        #expect(reopenedDeck.name == "Migrated deck")
        try reopened.close()
    }

    @Test("CloudKit options stay on the final live description without account access")
    func cloudKitOptionsStayOnFinalDescription() throws {
        let url = temporaryMigrationStoreURL()
        let prior = try makePriorDeckStore(at: url)
        try closeFixture(prior.container)
        defer { removeMigrationStoreFiles(at: url) }
        var observed: [(url: URL?, hasCloudKitOptions: Bool)] = []

        let controller = try PersistenceController(
            configuration: .cloudKit(
                storeURL: url,
                containerIdentifier: "iCloud.com.example.flashup"
            ),
            storeLoader: { container, completion in
                let description = container.persistentStoreDescriptions[0]
                observed.append((description.url, description.cloudKitContainerOptions != nil))
                if description.url?.path.contains("/Staged/") == true {
                    container.loadPersistentStores(completionHandler: completion)
                } else {
                    // The final callback is injected so this assertion never requires an Apple account.
                    completion(description, nil)
                }
            }
        )

        let artifact = try #require(controller.recoveryArtifact)
        #expect(artifact.isValid())
        #expect(observed.count == 2)
        #expect(observed[0].url?.path.contains("/Staged/") == true)
        #expect(observed[0].hasCloudKitOptions == false)
        #expect(observed[1].url == url)
        #expect(observed[1].hasCloudKitOptions)
        let stagedPath = artifact.directoryURL.appendingPathComponent("Staged").path
        #expect(FileManager.default.fileExists(atPath: stagedPath) == false)
        try controller.close()
    }
}
