import CoreData
import Foundation
@testable import FlashUpData

extension PersistenceControllerTests {
    func temporaryMigrationStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-persistence-migration-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Private.sqlite")
    }

    func removeMigrationStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            let candidate = suffix.isEmpty ? url : URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.removeItem(at: candidate)
        }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"))
    }

    func closeFixture(_ container: NSPersistentContainer) throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    func storeURLs(at url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func originalBytes(for urls: [URL]) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    func makePriorStore(at url: URL) throws -> NSPersistentContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "LegacyDeck"
        entity.managedObjectClassName = "NSManagedObject"
        let uuid = NSAttributeDescription()
        uuid.name = "uuid"
        uuid.attributeType = .UUIDAttributeType
        uuid.isOptional = true
        entity.properties = [uuid]
        model.entities = [entity]

        let container = NSPersistentContainer(name: "FlashUpPriorFixture", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }

        let object = NSEntityDescription.insertNewObject(forEntityName: "LegacyDeck", into: container.viewContext)
        object.setValue(UUID(), forKey: "uuid")
        try container.viewContext.save()
        return container
    }

    func makePriorDeckStore(at url: URL) throws -> (container: NSPersistentContainer, uuid: UUID) {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "CDDeck"
        entity.managedObjectClassName = "NSManagedObject"

        let uuid = NSAttributeDescription()
        uuid.name = "uuid"
        uuid.attributeType = .UUIDAttributeType
        uuid.isOptional = true
        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false
        name.defaultValue = ""
        entity.properties = [uuid, name]
        model.entities = [entity]

        let container = NSPersistentContainer(name: "FlashUpPriorDeckFixture", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }

        let identifier = UUID()
        let object = NSEntityDescription.insertNewObject(forEntityName: "CDDeck", into: container.viewContext)
        object.setValue(identifier, forKey: "uuid")
        object.setValue("Migrated deck", forKey: "name")
        try container.viewContext.save()
        return (container, identifier)
    }
}
