// swiftlint:disable file_length

import FlashUpData
import FlashUpDomain
import Observation
import OSLog
import SwiftUI

/// Composition root.
///
/// It owns the choice of repository implementation and nothing else knows which one is in
/// use. Shipping launches use the persistent Core Data repository; the in-memory repository
/// remains an explicit preview/recording oracle only.
@Observable
@MainActor
final class AppEnvironment { // swiftlint:disable:this type_body_length
    private final class StorageRetryProbe {
        var repositoryOpenCount = 0
    }

    struct StorageBundle {
        let library: any LibraryRepository
        let mediaStore: any MediaStore
    }

    typealias StorageFactory = @MainActor () async throws -> StorageBundle

    enum EraseFailure: String, Equatable {
        case library
        case media
        case reminders
    }

    /// Logger subsystem required by spec §0.2. Categories are added per subsystem.
    /// Logs carry metadata only — never card text.
    static let loggingSubsystem = "com.flashup.app"

    let logger: Logger
    var library: any LibraryRepository
    let reminders: any ReminderScheduling
    /// Attachment blobs (ADR-004 §6). Held here for the same reason as the library: the
    /// choice of implementation belongs to the composition root, and views only see the
    /// protocol — injected through the environment so `CardFaceView` can render a picture.
    var mediaStore: any MediaStore
    enum StorageState: Equatable {
        case bootstrapping
        case switching
        case ready
        case failed(LibraryRepositoryError)
    }
    private(set) var storageState: StorageState = .ready
    /// Identity for the mounted feature tree. A new ready bundle gets a new root identity so
    /// feature @State models cannot retain repository/session state from a prior profile.
    private(set) var storageGeneration: UInt64 = 0

    /// A remote-sync retry may fail while the local private replica remains usable. Keep
    /// that diagnostic separate from `storageState`, which is reserved for failures that
    /// prevent authoring/study from opening the local repository.
    private(set) var syncRetryError: LibraryRepositoryError?

    /// Retry is deliberately serialized at the composition root. Setting this before the
    /// first suspension closes the re-entrancy window where two recovery taps could otherwise
    /// create two coordinators for the same SQLite/CloudKit store.
    private(set) var isStorageRetrying = false
    private var storageRetryGeneration: UInt64 = 0
    private(set) var storageRetryOpenCount = 0
    var storageRetryRepositoryOpenCount: Int { storageRetryProbe.repositoryOpenCount }
    let isRetryProbeEnabled: Bool
    private let storageRetryProbe: StorageRetryProbe
    private let storageFactory: StorageFactory?
    private let accountStoreCoordinator: AccountStoreCoordinator?
    private let productionStorageUnavailable: Bool
    private var productionStorageBootstrapped = false
    private var productionBootstrapTask: Task<StorageBundle, Error>?
    private var accountTransitionTask: Task<Void, Never>?
    private var latestAccountTransitionGeneration: UInt64 = 0

    /// Details retained when opening the persistent store fails. The artifact is deliberately
    /// typed and opaque to the UI: support can receive a raw recovery directory without
    /// exposing framework paths or pretending that storage recovered successfully.
    struct StorageRecoveryContext: Equatable {
        let reason: PersistenceFailureReason
        let artifact: RecoveryArtifact?
    }
    private(set) var storageRecovery: StorageRecoveryContext?

    /// The chosen appearance lives here because two screens need it: Settings writes it and
    /// the root scene applies it. Holding it in either one alone means the other never hears
    /// about the change.
    var appearance: StudySettings.Appearance = .system

    /// What the root scene hands to `preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func loadAppearance() async {
        do {
            try await ensureProductionStorage()
            appearance = try await library.settings().appearance
        } catch let error as LibraryRepositoryError {
            storageState = .failed(error)
        } catch {
            storageState = .failed(.readFailed)
        }
    }

    func installDemoDeck() async throws {
        do {
            try await ensureProductionStorage()
            try await library.installDemoDeck()
        } catch let error as LibraryRepositoryError {
            storageState = .failed(error)
            throw error
        } catch {
            storageState = .failed(.writeFailed)
            throw LibraryRepositoryError.writeFailed
        }
    }

    /// Public sync retry seam used by Settings and recovery UI. The repository owns account
    /// mapping and history refresh; this composition root only exposes the outcome.
    func retrySync() async {
        do {
            try await library.retrySync()
            syncRetryError = nil
        } catch let error as LibraryRepositoryError {
            syncRetryError = error
        } catch {
            syncRetryError = .writeFailed
        }
    }

    /// Coordinates the irreversible local erase across the stores owned by the composition
    /// root. The Core Data repository also removes its migration recovery copies; media and
    /// notifications live outside that package boundary and are handled here.
    @discardableResult
    func eraseAllData() async -> Set<EraseFailure> {
        var failures = Set<EraseFailure>()
        do {
            try await library.deleteAllData()
        } catch {
            failures.insert(.library)
        }

        do {
            try await mediaStore.removeAll()
        } catch {
            failures.insert(.media)
        }

        if await reminders.apply(.init(isEnabled: false, hour: 20, minute: 30)) == false {
            failures.insert(.reminders)
        }
        UserDefaults.standard.removeObject(forKey: "didFinishOnboarding")

        if failures.isEmpty {
            storageState = .ready
            storageRecovery = nil
        } else {
            storageState = .failed(.writeFailed)
        }
        return failures
    }

    func retryStorage() async { // swiftlint:disable:this cyclomatic_complexity function_body_length
        let bootstrapPending = accountStoreCoordinator != nil && !productionStorageBootstrapped
        guard (bootstrapPending || (ifFailedStorageState())) && DemoMode.allFromEnvironment() == nil else { return }
        guard !isStorageRetrying else { return }
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["FLASHUP_UI_TEST_LOCAL"] != "1",
              environment["FLASHUP_UI_TEST_FAILURE"] != "1" || isRetryProbeEnabled else { return }
#endif

        isStorageRetrying = true
        storageRetryGeneration &+= 1
        let generation = storageRetryGeneration
        defer {
            if storageRetryGeneration == generation {
                isStorageRetrying = false
            }
        }

        if accountStoreCoordinator != nil {
            storageState = .switching
            revokeProductionPorts()
            do {
                try await ensureProductionStorage()
                guard storageRetryGeneration == generation else { return }
            } catch {
                storageState = .failed(.persistenceUnavailable)
                storageRecovery = Self.recoveryContext(from: error)
            }
            return
        }

        if let oldLibrary = library as? CoreDataLibraryRepository {
            do {
                try await oldLibrary.close()
            } catch {
                storageState = .failed(.writeFailed)
                return
            }
        }
        storageState = .failed(.persistenceUnavailable)
        do {
            let replacement = try await openStorage()
            guard storageRetryGeneration == generation else {
                if let superseded = replacement.library as? CoreDataLibraryRepository {
                    try? await superseded.close()
                }
                return
            }
            installProductionBundle(replacement)
        } catch {
            library = CoreDataLibraryRepository.unavailable(.persistenceUnavailable)
            mediaStore = UnavailableMediaStore()
            storageState = .failed(.persistenceUnavailable)
            storageRecovery = Self.recoveryContext(from: error)
        }
    }

    private func openStorage() async throws -> StorageBundle {
        storageRetryOpenCount += 1
        if let storageFactory {
            return try await storageFactory()
        }
        if let accountStoreCoordinator {
            let bundle = try await accountStoreCoordinator.open()
            return StorageBundle(library: bundle.library, mediaStore: bundle.mediaStore)
        }
        if productionStorageUnavailable {
            throw LibraryRepositoryError.persistenceUnavailable
        }
        throw LibraryRepositoryError.persistenceUnavailable
    }

    init( // swiftlint:disable:this function_body_length
        library: (any LibraryRepository)? = nil,
        reminders: (any ReminderScheduling)? = nil,
        mediaStore: (any MediaStore)? = nil,
        storageFactory: StorageFactory? = nil
    ) {
        let logger = Logger(subsystem: Self.loggingSubsystem, category: "app")
        self.logger = logger
        let storageRetryProbe = StorageRetryProbe()
        self.storageRetryProbe = storageRetryProbe
        self.storageFactory = storageFactory ?? Self.debugRetryFactory(probe: storageRetryProbe)
#if DEBUG
        self.isRetryProbeEnabled = ProcessInfo.processInfo.environment["FLASHUP_UI_TEST_RETRY_PROBE"] == "1"
#else
        self.isRetryProbeEnabled = false
#endif
        let demoModes = DemoMode.allFromEnvironment()
        let localUITest = Self.localUITestConfiguration()
        let usesProductionAccountRouting = library == nil
            && demoModes == nil
            && localUITest.root == nil
            && !localUITest.failed
        let libraryResolution = Self.resolveLibrary(
            explicit: library,
            demoModes: demoModes,
            localUITest: localUITest,
            logger: logger
        )
        if usesProductionAccountRouting {
            self.library = CoreDataLibraryRepository.unavailable(.persistenceUnavailable)
        } else {
            self.library = libraryResolution.library
        }
        // A recording session must never schedule a real notification: a banner dropping
        // into frame ruins a take that is otherwise finished (spec §3.1).
        let liveReminders: any ReminderScheduling = demoModes == nil && localUITest.root == nil
            ? ReminderScheduler()
            : StubReminderScheduler(grantsPermission: true)
        self.reminders = reminders ?? StubReminderScheduler.fromEnvironment() ?? liveReminders
        let mediaResolution = usesProductionAccountRouting
            ? MediaResolution(store: UnavailableMediaStore(), failed: false)
            : Self.resolveMediaStore(
                explicit: mediaStore,
                demoModes: demoModes,
                localUITestRoot: localUITest.root
            )
        self.mediaStore = mediaResolution.store
        self.storageState = usesProductionAccountRouting ? .ready : mediaResolution.failed
            ? .failed(.persistenceUnavailable)
            : libraryResolution.state
        if usesProductionAccountRouting {
            self.storageState = .bootstrapping
        }
        self.storageRecovery = usesProductionAccountRouting ? nil : libraryResolution.recovery
        if usesProductionAccountRouting,
           let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let coordinator = AccountStoreCoordinator(
                rootURL: support.appendingPathComponent("FlashApp", isDirectory: true),
                containerIdentifier: "iCloud.com.flashup.app"
            )
            self.accountStoreCoordinator = coordinator
            self.productionStorageUnavailable = false
            self.productionBootstrapTask = nil
            self.accountTransitionTask = Task { @MainActor [weak self, coordinator] in
                for await event in coordinator.transitionEvents() {
                    self?.consumeAccountTransition(event)
                }
            }
        } else {
            self.accountStoreCoordinator = nil
            self.productionStorageUnavailable = usesProductionAccountRouting
            self.productionBootstrapTask = nil
            self.accountTransitionTask = nil
        }
    }

    private func ifFailedStorageState() -> Bool {
        if case .failed = storageState { return true }
        return false
    }

    private func ensureProductionStorage() async throws {
        guard accountStoreCoordinator != nil, !productionStorageBootstrapped else { return }
        if let productionBootstrapTask {
            _ = try await productionBootstrapTask.value
            return
        }
        storageState = .bootstrapping
        revokeProductionPorts()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw LibraryRepositoryError.persistenceUnavailable }
            let replacement = try await self.openStorage()
            // The joiner awaits this task, so installation is part of the single-flight
            // operation rather than a follow-up scheduled by the event consumer.
            self.installProductionBundle(replacement)
            return replacement
        }
        productionBootstrapTask = task
        defer { productionBootstrapTask = nil }
        do {
            _ = try await task.value
        } catch let error as AccountStoreRoutingError where error == .transitionSuperseded {
            // A newer account transition owns the outcome; its generation-bound stream will
            // install the replacement or publish the real failure.
        } catch {
            storageState = .failed(.persistenceUnavailable)
            storageRecovery = Self.recoveryContext(from: error)
            throw error
        }
    }

    private func installProductionBundle(_ replacement: StorageBundle, generation: UInt64? = nil) {
        library = replacement.library
        mediaStore = replacement.mediaStore
        productionStorageBootstrapped = true
        if let generation {
            storageGeneration = max(storageGeneration, generation)
        } else {
            storageGeneration &+= 1
        }
        storageState = .ready
        storageRecovery = nil
    }

    private func revokeProductionPorts() {
        guard accountStoreCoordinator != nil else { return }
        productionStorageBootstrapped = false
        library = CoreDataLibraryRepository.unavailable(.persistenceUnavailable)
        mediaStore = UnavailableMediaStore()
    }

    private func consumeAccountTransition(_ event: AccountStoreTransitionEvent) {
        let generation: UInt64
        switch event {
        case let .bootstrapping(value), let .switching(value), let .ready(value, _), let .failed(value, _):
            generation = value
        }
        guard generation >= latestAccountTransitionGeneration else { return }
        latestAccountTransitionGeneration = generation

        switch event {
        case .bootstrapping:
            storageState = .bootstrapping
            revokeProductionPorts()
        case .switching:
            storageState = .switching
            revokeProductionPorts()
        case let .ready(readyGeneration, bundle):
            installProductionBundle(
                StorageBundle(library: bundle.library, mediaStore: bundle.mediaStore),
                generation: readyGeneration
            )
        case let .failed(_, error):
            guard error != .transitionSuperseded else { return }
            revokeProductionPorts()
            storageState = .failed(.persistenceUnavailable)
            storageRecovery = nil
        }
    }

    private struct LibraryResolution {
        let library: any LibraryRepository
        let state: StorageState
        let recovery: StorageRecoveryContext?
    }

    private struct LocalUITestConfiguration {
        let root: URL?
        let failed: Bool
        let recovery: StorageRecoveryContext?
    }

    private struct MediaResolution {
        let store: any MediaStore
        let failed: Bool
    }

    private static func localUITestConfiguration() -> LocalUITestConfiguration {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["FLASHUP_UI_TEST_FAILURE"] == "1" {
            do {
                let root = try localUITestRoot()
                let artifactDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
                    .appendingPathComponent("ui-test-artifact", isDirectory: true)
                try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
                let rawStore = artifactDirectory.appendingPathComponent("Private.sqlite")
                try Data("UI test recovery artifact".utf8).write(to: rawStore)
                let artifact = RecoveryArtifact(
                    directoryURL: artifactDirectory,
                    files: [RecoveryFile(
                        url: rawStore,
                        byteCount: Int64("UI test recovery artifact".utf8.count),
                        sha256: String(repeating: "0", count: 64)
                    )]
                )
                return LocalUITestConfiguration(
                    root: nil,
                    failed: true,
                    recovery: StorageRecoveryContext(reason: .storeUnreadable, artifact: artifact)
                )
            } catch {
                return LocalUITestConfiguration(root: nil, failed: true, recovery: nil)
            }
        }
        guard environment["FLASHUP_UI_TEST_LOCAL"] == "1" else {
            return LocalUITestConfiguration(root: nil, failed: false, recovery: nil)
        }
        do {
            return LocalUITestConfiguration(root: try localUITestRoot(), failed: false, recovery: nil)
        } catch {
            return LocalUITestConfiguration(root: nil, failed: true, recovery: nil)
        }
#else
        return LocalUITestConfiguration(root: nil, failed: false, recovery: nil)
#endif
    }

    private static func resolveLibrary(
        explicit: (any LibraryRepository)?,
        demoModes: [DemoMode]?,
        localUITest: LocalUITestConfiguration,
        logger: Logger
    ) -> LibraryResolution {
        if let explicit {
            return LibraryResolution(library: explicit, state: .ready, recovery: nil)
        }
#if DEBUG
        if localUITest.failed {
            return LibraryResolution(
                library: CoreDataLibraryRepository.unavailable(.persistenceUnavailable),
                state: .failed(.persistenceUnavailable),
                recovery: localUITest.recovery
            )
        }
#endif
        if let localUITestRoot = localUITest.root {
            do {
                let library = try CoreDataLibraryRepository(
                    configuration: .onDisk(
                        storeURL: localUITestRoot.appendingPathComponent("Private.sqlite")
                    ),
                    sessionURL: localUITestRoot.appendingPathComponent("session-state.json")
                )
                return LibraryResolution(library: library, state: .ready, recovery: nil)
            } catch {
                return LibraryResolution(
                    library: CoreDataLibraryRepository.unavailable(.persistenceUnavailable),
                    state: .failed(.persistenceUnavailable),
                    recovery: recoveryContext(from: error)
                )
            }
        }
        if let demoModes {
            guard let library = demoLibrary(demoModes, logger: logger) else {
                return LibraryResolution(
                    library: CoreDataLibraryRepository.unavailable(.persistenceUnavailable),
                    state: .failed(.persistenceUnavailable),
                    recovery: nil
                )
            }
            return LibraryResolution(library: library, state: .ready, recovery: nil)
        }
        // The production path is opened asynchronously by AccountStoreCoordinator after
        // identity preflight. This branch is retained only for explicit failure injection;
        // it never opens a CloudKit store or substitutes an in-memory repository.
        return LibraryResolution(
            library: CoreDataLibraryRepository.unavailable(.persistenceUnavailable),
            state: .failed(.persistenceUnavailable),
            recovery: nil
        )
    }

    private static func resolveMediaStore(
        explicit: (any MediaStore)?,
        demoModes: [DemoMode]?,
        localUITestRoot: URL?
    ) -> MediaResolution {
        if let explicit {
            return MediaResolution(store: explicit, failed: false)
        }
        if let localUITestRoot {
            do {
                return MediaResolution(
                    store: try FileMediaStore(
                        directory: localUITestRoot.appendingPathComponent("Media", isDirectory: true)
                    ),
                    failed: false
                )
            } catch {
                return MediaResolution(store: UnavailableMediaStore(), failed: true)
            }
        }
        if demoModes == nil {
            do {
                return MediaResolution(store: try FileMediaStore(), failed: false)
            } catch {
                return MediaResolution(store: UnavailableMediaStore(), failed: true)
            }
        }
        return MediaResolution(store: InMemoryMediaStore(), failed: false)
    }

    private static func recoveryContext(from error: Error) -> StorageRecoveryContext? {
        if let persistenceError = error as? PersistenceError {
            switch persistenceError {
            case let .storeLoadFailed(artifact, reason):
                return StorageRecoveryContext(reason: reason, artifact: artifact)
            case .recoverySnapshotFailed:
                return StorageRecoveryContext(reason: .corruptStore, artifact: nil)
            default:
                return nil
            }
        }
        return nil
    }

    private static func debugRetryFactory(probe: StorageRetryProbe) -> StorageFactory? {
#if DEBUG
        guard ProcessInfo.processInfo.environment["FLASHUP_UI_TEST_RETRY_PROBE"] == "1" else {
            return nil
        }
        return {
            // Keep the injected opening in flight long enough for a second recovery action to
            // attempt re-entry. The guard in retryStorage must make this one open observable.
            let root = try localUITestRoot()
            let mediaDirectory = root.appendingPathComponent("Media", isDirectory: true)
            if ProcessInfo.processInfo.environment["FLASHUP_UI_TEST_MEDIA_FAILURE"] == "1" {
                try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
                try Data("not a media manifest".utf8).write(
                    to: mediaDirectory.appendingPathComponent("index.json"),
                    options: [.atomic]
                )
            } else {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            // The media store is intentionally constructed first. A corrupt manifest must
            // fail before a Core Data/CloudKit owner is ever opened.
            let mediaStore = try FileMediaStore(directory: mediaDirectory)
            let library = try CoreDataLibraryRepository(
                configuration: .onDisk(
                    storeURL: root.appendingPathComponent("Private.sqlite")
                ),
                sessionURL: root.appendingPathComponent("session-state.json")
            )
            probe.repositoryOpenCount += 1
            return StorageBundle(library: library, mediaStore: mediaStore)
        }
#else
        return nil
#endif
    }

#if DEBUG
    private static func localUITestRoot() throws -> URL {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw LibraryRepositoryError.persistenceUnavailable }
        let runID = ProcessInfo.processInfo.environment["FLASHUP_UI_TEST_RUN_ID"] ?? "default"
        let root = support
            .appendingPathComponent("FlashUpUITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
#endif

    /// The library the marketing pipeline records against.
    ///
    /// Reached only when `DEMO_MODE=1` was set, so the shipping path is untouched. When the
    /// deck cannot be loaded an empty library is returned rather than the ordinary demo
    /// seed: a flow must fail on its first assertion instead of quietly recording the wrong
    /// deck, which only becomes visible once the footage is on the timeline.
    private static func demoLibrary(_ modes: [DemoMode], logger: Logger) -> (any LibraryRepository)? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.fault("Demo mode requested but the Documents directory is unavailable")
            return nil
        }

        do {
            return try InMemoryLibrary.demo(modes, documents: documents)
        } catch {
            // Deck names are pipeline configuration, not card text, so logging the slug is
            // within the privacy rule that keeps user content out of diagnostics.
            let slugs = modes.map(\.slug).joined(separator: ",")
            logger.fault("Demo decks '\(slugs, privacy: .public)' failed to seed: \(error)")
            return nil
        }
    }
}
