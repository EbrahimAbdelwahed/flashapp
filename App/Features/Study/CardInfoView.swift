import FlashUpDomain
import SwiftUI

/// What the scheduler knows about one card, in the learner's terms.
///
/// Deliberately no stability or difficulty: the FSRS internals are in `CardInfo` but they
/// mean nothing to someone mid-session, and showing them would hand the user a dial they
/// cannot turn (`docs/ux-principles.md` §2).
struct CardInfoView: View {
    let info: CardInfo
    let onDone: () -> Void

    /// Fixed at presentation so every row on screen agrees on what "now" is.
    private let now = Date()

    var body: some View {
        NavigationStack {
            List {
                // No section header: the row label already says "State", and a header
                // repeating it would just be the same word twice.
                Section {
                    LabeledContent("study.info.state") { Text(stateTitle) }
                    if info.isSuspended {
                        Label("study.info.suspended", systemImage: "pause.circle")
                            .foregroundStyle(Palette.warning)
                    }
                    if info.isBuried(at: now), let until = info.schedule?.buriedUntil {
                        Label {
                            Text("study.info.buried \(until.formatted(date: .abbreviated, time: .omitted))")
                        } icon: {
                            Image(systemName: "moon.zzz")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .paperRows()

                Section("study.info.schedule") {
                    LabeledContent("study.info.due") { Text(dueCaption) }
                    LabeledContent("study.info.reps") { Text(info.schedule?.reps ?? 0, format: .number) }
                    LabeledContent("study.info.lapses") { Text(info.schedule?.lapses ?? 0, format: .number) }
                    LabeledContent("study.info.last_review") { Text(lastReviewCaption) }
                }
                .paperRows()

                Section("study.info.history") {
                    if info.logs.isEmpty {
                        Text("study.info.history.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(info.logs.prefix(historyLimit)) { log in
                            HistoryRow(log: log)
                        }
                    }
                }
                .paperRows()
            }
            .screenCanvas()
            .navigationTitle("study.info.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("study.info.done", action: onDone)
                }
            }
        }
        .accessibilityIdentifier("study.info")
    }

    /// Enough to see the recent pattern without turning the sheet into a log viewer.
    private let historyLimit = 10

    private var stateTitle: LocalizedStringKey {
        guard let schedule = info.schedule, !info.isNew else { return "study.info.state.new" }
        switch schedule.state {
        case .new: return "study.info.state.new"
        case .learning: return "study.info.state.learning"
        case .review: return "study.info.state.review"
        case .relearning: return "study.info.state.relearning"
        }
    }

    private var dueCaption: String {
        // A card that has never been answered has no meaningful date: its placeholder due
        // date is an implementation detail, not something to show.
        guard let schedule = info.schedule, !info.isNew else {
            return String(localized: "study.info.due.now")
        }
        if schedule.dueAt <= now {
            return String(localized: "study.info.due.now")
        }
        return IntervalFormatter.short(schedule.dueAt.timeIntervalSince(now))
    }

    private var lastReviewCaption: String {
        guard let last = info.schedule?.lastReviewedAt else {
            return String(localized: "study.info.never")
        }
        return last.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One past answer: when it happened and how it was graded.
private struct HistoryRow: View {
    let log: ReviewLog

    var body: some View {
        LabeledContent {
            Text(gradeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        } label: {
            Text(log.reviewedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var gradeTitle: LocalizedStringKey {
        switch log.grade {
        case .again: "grade.again"
        case .hard: "grade.hard"
        case .good: "grade.good"
        case .easy: "grade.easy"
        }
    }

    /// The same reading as the grade buttons, so a row is recognisable at a glance. Text
    /// variants, because here the colour carries meaning on type rather than on a fill.
    private var tint: Color {
        switch log.grade {
        case .again: Palette.destructive
        case .hard: Palette.warning
        case .good: Palette.successText
        case .easy: Palette.slateText
        }
    }
}
