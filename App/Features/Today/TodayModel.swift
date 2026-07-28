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

    init(library: any LibraryRepository) {
        self.library = library
    }

    var isLoading: Bool { snapshot == nil }

    func refresh() async {
        snapshot = await library.todaySnapshot(now: Date())
        await checkForResumableSession()
    }

    private func checkForResumableSession() async {
        guard let session = await library.storedSession(), session.isResumable(at: Date()) else {
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
        await library.storeSession(nil)
        resumableScope = nil
        resumableCount = 0
    }
}
