import CloudKit
import CoreData
import Foundation

internal typealias PersistentStoreLoader = (
    NSPersistentContainer,
    @escaping (NSPersistentStoreDescription, Error?) -> Void
) -> Void

/// Loads the single V1 `Private.sqlite` store and exposes the contexts used by repositories.
///
/// A controller owns no fallback in-memory production behavior. `inMemory` is a deterministic
/// test/preview configuration; production callers must pass `.cloudKit` with the final
/// container identifier once the human account/schema gate is complete.
public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentCloudKitContainer
    public let configuration: PersistenceConfiguration
    public let storeDescription: NSPersistentStoreDescription
    public private(set) var recoveryArtifact: RecoveryArtifact?

    private let lifecycleCondition = NSCondition()
    private var activeBackgroundOperations = 0
    private var closed = false
    private var closing = false

    public var viewContext: NSManagedObjectContext { container.viewContext }
    public var isClosed: Bool { lifecycleCondition.withLock { closed } }
    internal var isClosingForTesting: Bool { lifecycleCondition.withLock { closing } }
    internal var activeBackgroundOperationCount: Int {
        lifecycleCondition.withLock { activeBackgroundOperations }
    }

    public convenience init(
        configuration: PersistenceConfiguration = .inMemory,
        fileManager: FileManager = .default
    ) throws {
        try self.init(configuration: configuration, fileManager: fileManager, storeLoader: nil)
    }

    internal init(
        configuration: PersistenceConfiguration,
        fileManager: FileManager = .default,
        storeLoader: PersistentStoreLoader?
    ) throws {
        self.configuration = configuration
        let model = try Self.loadModel()
        let normalizedStoreURL = try Self.validatedStoreURL(for: configuration)
        let description = try Self.makeDescription(
            configuration: configuration,
            storeURL: normalizedStoreURL,
            fileManager: fileManager
        )
        let preflight = normalizedStoreURL.map {
            MigrationRecovery.preflight(at: $0, model: model, fileManager: fileManager)
        } ?? .newStore
        var recoveryArtifact: RecoveryArtifact?
        if preflight == .migrationRequired || preflight == .unreadable,
           let normalizedStoreURL {
            recoveryArtifact = try MigrationRecovery.preserveStoreFiles(
                at: normalizedStoreURL,
                fileManager: fileManager
            )
        }

        let container = try Self.makeContainer(
            request: ContainerLoadRequest(
                model: model,
                preflight: preflight,
                storeURL: normalizedStoreURL,
                description: description,
                recoveryArtifact: recoveryArtifact,
                fileManager: fileManager,
                storeLoader: storeLoader
            )
        )

        let loadError = Self.loadPersistentStores(
            in: container,
            description: description,
            loader: storeLoader
        )
        if loadError != nil {
            throw PersistenceError.storeLoadFailed(
                recoveryArtifact: recoveryArtifact,
                reason: Self.failureReason(for: preflight)
            )
        }

        self.container = container
        self.storeDescription = description
        self.recoveryArtifact = recoveryArtifact
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Runs one repository operation on a controller-owned background context.
    /// The context is registered only for the duration of this call and is saved before release.
    public func performBackgroundTask<T>(
        _ operation: (NSManagedObjectContext) throws -> T
    ) throws -> T {
        lifecycleCondition.lock()
        guard !closed, !closing else {
            lifecycleCondition.unlock()
            throw PersistenceError.backgroundWorkRejected
        }
        activeBackgroundOperations += 1
        lifecycleCondition.unlock()

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        defer {
            lifecycleCondition.lock()
            activeBackgroundOperations -= 1
            lifecycleCondition.broadcast()
            lifecycleCondition.unlock()
        }

        var result: Result<T, Error> = .failure(PersistenceError.storeCloseFailed)
        context.performAndWait {
            do {
                let value = try operation(context)
                if context.hasChanges { try context.save() }
                result = .success(value)
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }

    /// Saves pending view-context changes without deleting or replacing the store on failure.
    public func save() throws {
        var saveError: Error?
        viewContext.performAndWait {
            guard viewContext.hasChanges else { return }
            do {
                try viewContext.save()
            } catch {
                saveError = error
            }
        }
        if saveError != nil { throw PersistenceError.storeCloseFailed }
    }

    /// Rejects new background work, waits for active operations, then unloads the store.
    public func close() throws {
        lifecycleCondition.lock()
        guard !closed else {
            lifecycleCondition.unlock()
            return
        }
        closing = true
        while activeBackgroundOperations > 0 { lifecycleCondition.wait() }
        lifecycleCondition.unlock()

        var didClose = false
        defer {
            if !didClose {
                lifecycleCondition.lock()
                closing = false
                lifecycleCondition.broadcast()
                lifecycleCondition.unlock()
            }
        }

        do {
            try save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            lifecycleCondition.lock()
            closed = true
            closing = false
            lifecycleCondition.broadcast()
            lifecycleCondition.unlock()
            didClose = true
        } catch {
            throw PersistenceError.storeCloseFailed
        }
    }

    internal static var bundledModelURL: URL? {
        Bundle.module.url(forResource: "FlashUpRuntime", withExtension: "momd")
    }

    public static func loadModel() throws -> NSManagedObjectModel {
        guard let modelURL = bundledModelURL,
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw PersistenceError.modelUnavailable
        }
        return model
    }

    /// Builds a description without loading it. This is the deterministic seam for checking
    /// private CloudKit configuration while the Apple account/schema gate is still human-owned.
    public static func storeDescription(
        for configuration: PersistenceConfiguration,
        fileManager: FileManager = .default
    ) throws -> NSPersistentStoreDescription {
        let storeURL = try validatedStoreURL(for: configuration)
        return try makeDescription(
            configuration: configuration,
            storeURL: storeURL,
            fileManager: fileManager
        )
    }

}

private struct ContainerLoadRequest {
    let model: NSManagedObjectModel
    let preflight: MigrationRecovery.Preflight
    let storeURL: URL?
    let description: NSPersistentStoreDescription
    let recoveryArtifact: RecoveryArtifact?
    let fileManager: FileManager
    let storeLoader: PersistentStoreLoader?
}

private extension PersistenceController {
    static func makeContainer(request: ContainerLoadRequest) throws -> NSPersistentCloudKitContainer {
        if request.preflight == .migrationRequired,
           let storeURL = request.storeURL,
           let recoveryArtifact = request.recoveryArtifact {
            let stagedURL = try MigrationRecovery.stageStoreFiles(
                from: recoveryArtifact,
                fileManager: request.fileManager
            )
            let stagedDescription = stagedDescription(from: request.description, at: stagedURL)
            let stagedContainer = NSPersistentContainer(name: "FlashUp", managedObjectModel: request.model)
            let stagedLoadError = loadPersistentStores(
                in: stagedContainer,
                description: stagedDescription,
                loader: request.storeLoader
            )
            if stagedLoadError != nil {
                try? unload(stagedContainer)
                MigrationRecovery.discardStagedStore(at: stagedURL, fileManager: request.fileManager)
                throw PersistenceError.storeLoadFailed(
                    recoveryArtifact: recoveryArtifact,
                    reason: .migrationFailed
                )
            }

            do {
                try unload(stagedContainer)
                try MigrationRecovery.adoptStagedStore(at: stagedURL, to: storeURL, model: request.model)
                MigrationRecovery.discardStagedStore(at: stagedURL, fileManager: request.fileManager)
            } catch {
                try? unload(stagedContainer)
                MigrationRecovery.discardStagedStore(at: stagedURL, fileManager: request.fileManager)
                throw PersistenceError.storeLoadFailed(
                    recoveryArtifact: recoveryArtifact,
                    reason: .migrationFailed
                )
            }
        }
        return NSPersistentCloudKitContainer(name: "FlashUp", managedObjectModel: request.model)
    }

    static func loadPersistentStores(
        in container: NSPersistentContainer,
        description: NSPersistentStoreDescription,
        loader: PersistentStoreLoader?
    ) -> Error? {
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        let completion: (NSPersistentStoreDescription, Error?) -> Void = { _, error in
            loadError = error
            semaphore.signal()
        }
        if let loader {
            loader(container, completion)
        } else {
            container.loadPersistentStores(completionHandler: completion)
        }
        semaphore.wait()
        return loadError
    }

    static func unload(_ container: NSPersistentContainer) throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    static func stagedDescription(
        from description: NSPersistentStoreDescription,
        at storeURL: URL
    ) -> NSPersistentStoreDescription {
        let staged = NSPersistentStoreDescription(url: storeURL)
        staged.type = description.type
        for (key, value) in description.options {
            staged.setOption(value, forKey: key)
        }
        staged.cloudKitContainerOptions = nil
        staged.shouldMigrateStoreAutomatically = true
        staged.shouldInferMappingModelAutomatically = true
        return staged
    }

    static func validatedStoreURL(for configuration: PersistenceConfiguration) throws -> URL? {
        switch configuration.kind {
        case .inMemory:
            return nil
        case .onDisk, .cloudKit:
            guard let storeURL = configuration.storeURL else { throw PersistenceError.storeURLRequired }
            let standardizedURL = storeURL.standardizedFileURL
            guard standardizedURL.isFileURL,
                  standardizedURL.pathExtension == "sqlite",
                  standardizedURL.lastPathComponent == "Private.sqlite" else {
                throw PersistenceError.invalidStoreURL
            }
            return standardizedURL
        }
    }

    static func makeDescription(
        configuration: PersistenceConfiguration,
        storeURL: URL?,
        fileManager: FileManager
    ) throws -> NSPersistentStoreDescription {
        switch configuration.kind {
        case .inMemory:
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            configureCommonOptions(description)
            return description
        case .onDisk, .cloudKit:
            guard let storeURL else { throw PersistenceError.storeURLRequired }
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            // Live stores are never migrated in place. Incompatible metadata is loaded
            // through `stagedDescription` and adopted only after staged migration succeeds.
            description.shouldMigrateStoreAutomatically = false
            description.shouldInferMappingModelAutomatically = false
            configureCommonOptions(description)

            if case let .cloudKit(containerIdentifier) = configuration.kind {
                guard containerIdentifier.hasPrefix("iCloud."), containerIdentifier.count > 7 else {
                    throw PersistenceError.invalidCloudKitContainerIdentifier
                }
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                // The SDK refines this Objective-C integer property for Swift as
                // `__databaseScope`; the raw value is CKDatabase.Scope.private (2).
                options.__databaseScope = CKDatabase.Scope.private.rawValue
                description.cloudKitContainerOptions = options
            }
            return description
        }
    }

    static func configureCommonOptions(_ description: NSPersistentStoreDescription) {
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    static func failureReason(for preflight: MigrationRecovery.Preflight) -> PersistenceFailureReason {
        switch preflight {
        case .migrationRequired:
            .migrationFailed
        case .unreadable:
            .corruptStore
        case .compatible, .newStore:
            .storeUnreadable
        }
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
