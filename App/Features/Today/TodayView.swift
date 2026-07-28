import FlashUpDomain
import SwiftUI

/// The app's front door.
///
/// `docs/ux-principles.md` §2: the screen opens on the action. The primary control is the
/// first thing under the counts and is always in the same place, so a returning user starts
/// studying without reading anything.
struct TodayView: View {
    @State private var model: TodayModel
    /// Presentation state belongs to the view, not the model: the session is a piece of
    /// navigation, and keeping it here survives the model being rebuilt.
    @State private var studyingScope: StudyScope?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(library: any LibraryRepository) {
        _model = State(initialValue: TodayModel(library: library))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.loose) {
                if let snapshot = model.snapshot {
                    counts(snapshot)
                    studyButton(snapshot)
                    decks(snapshot)
                } else {
                    ProgressView().padding(.top, Spacing.sectionGap)
                }
            }
            .padding(Spacing.normal)
            .animation(Motion.reveal(reduceMotion: reduceMotion), value: model.snapshot)
        }
        .navigationTitle("tab.today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    StatisticsView(library: model.library)
                } label: {
                    Label("today.statistics", systemImage: "chart.bar")
                }
                .accessibilityIdentifier("today.statistics")
            }
        }
        .alert("today.resume.title", isPresented: $model.isOfferingResume) {
            Button("today.resume.action") { studyingScope = model.resumableScope ?? .allDecks }
            Button("today.resume.discard", role: .cancel) { Task { await model.discardSession() } }
        } message: {
            Text("today.resume.message \(model.resumableCount)")
        }
        .task { await model.refresh() }
        .fullScreenCover(
            item: $studyingScope,
            onDismiss: { Task { await model.refresh() } },
            content: { scope in StudySessionView(library: model.library, scope: scope) }
        )
    }

    // MARK: - Sections

    private func counts(_ snapshot: TodaySnapshot) -> some View {
        HStack(spacing: Spacing.normal) {
            CountTile(
                value: snapshot.dueCount,
                caption: "today.due",
                systemImage: "clock.arrow.circlepath",
                tint: .orange
            )
            CountTile(
                value: snapshot.newCount,
                caption: "today.new",
                systemImage: "sparkles",
                tint: .blue
            )
        }
    }

    @ViewBuilder
    private func studyButton(_ snapshot: TodaySnapshot) -> some View {
        if snapshot.hasWorkToDo {
            PrimaryActionButton(
                title: "today.study_now",
                subtitle: LocalizedStringKey("today.study_now.subtitle \(snapshot.dueCount + snapshot.newCount)"),
                systemImage: "play.fill"
            ) {
                studyingScope = .allDecks
            }
        } else {
            CaughtUpCard(streakDays: snapshot.metrics.streakDays)
        }
    }

    private func decks(_ snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("today.your_decks")
                .font(.headline)
                .padding(.leading, Spacing.tight)

            ForEach(snapshot.decks) { summary in
                DeckRow(summary: summary) {
                    studyingScope = .deck(summary.deck.id)
                }
            }
        }
    }
}

/// `StudyScope` becomes presentable so the session can be driven straight from a tap.
extension StudyScope: @retroactive Identifiable {
    public var id: String {
        switch self {
        case .allDecks: "all"
        case let .deck(uuid): uuid.uuidString
        }
    }
}
