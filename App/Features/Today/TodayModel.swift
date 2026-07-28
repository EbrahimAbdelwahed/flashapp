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

    init(library: any LibraryRepository) {
        self.library = library
    }

    var isLoading: Bool { snapshot == nil }

    func refresh() async {
        snapshot = await library.todaySnapshot(now: Date())
    }
}
