import FlashUpDomain
import Foundation
import Observation

/// Screen state for Today.
///
/// Reads through `LibraryRepository`, so it is unaffected by whether the data comes from
/// the in-memory preview store or the Core Data stack that replaces it.
@Observable
@MainActor
final class TodayModel {
    /// Handed to the study session the user starts from here.
    let library: any LibraryRepository

    private(set) var snapshot: TodaySnapshot?
    /// A session left unfinished on this device, offered back once (spec §A6.6).
    var isOfferingResume = false
    private(set) var resumableScope: StudyScope?
    private(set) var resumableCount = 0
    private(set) var errorMessage: String?

    init(library: any LibraryRepository) {
        self.library = library
    }

    var isLoading: Bool { snapshot == nil }

    func refresh() async {
        do {
            snapshot = try await library.todaySnapshot(now: Date())
        } catch {
            snapshot = nil
            resumableScope = nil
            resumableCount = 0
            errorMessage = String(localized: "today.error.unavailable")
            return
        }
        errorMessage = nil
        await checkForResumableSession()
    }

    private func checkForResumableSession() async {
        let session: SessionState?
        do {
            session = try await library.storedSession()
        } catch {
            resumableScope = nil
            resumableCount = 0
            errorMessage = String(localized: "today.error.unavailable")
            return
        }
        guard let session, session.isResumable(at: Date()) else {
            resumableScope = nil
            resumableCount = 0
            return
        }
        // Offer it once: nagging about an abandoned session is worse than losing it.
        guard resumableScope == nil else { return }
        resumableScope = session.scope.scope
        resumableCount = session.remainingCardIDs.count
        isOfferingResume = true
    }

    func discardSession() async {
        do { try await library.storeSession(nil) } catch {
            errorMessage = String(localized: "today.error.unavailable")
            return
        }
        resumableScope = nil
        resumableCount = 0
    }

    func clearError() {
        errorMessage = nil
    }
}
