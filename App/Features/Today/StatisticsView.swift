import Charts
import FlashUpDomain
import SwiftUI

/// Detail pushed from Today (spec §A11.2): retention, history and per-deck workload.
struct StatisticsView: View {
    let library: any LibraryRepository

    @State private var metrics: StudyMetrics?
    @State private var decks: [DeckSummary] = []

    var body: some View {
        List {
            if let metrics {
                Section("stats.overview") {
                    LabeledContent("stats.studied_today") {
                        Text(metrics.studiedToday, format: .number).monospacedDigit()
                    }
                    LabeledContent("stats.streak") {
                        Text("stats.days \(metrics.streakDays)").monospacedDigit()
                    }
                    LabeledContent("stats.retention_7") { retention(metrics.retention7Days) }
                    LabeledContent("stats.retention_30") { retention(metrics.retention30Days) }
                }
                .paperRows()

                Section("stats.history") {
                    Chart(metrics.dailyReviews) { day in
                        BarMark(
                            x: .value(String(localized: "stats.axis_day"), day.day, unit: .day),
                            y: .value(String(localized: "stats.axis_reviews"), day.count)
                        )
                        .foregroundStyle(Palette.new)
                    }
                    .frame(height: 180)
                    .accessibilityLabel("stats.history")
                    .accessibilityValue("stats.history_value \(metrics.dailyReviews.reduce(0) { $0 + $1.count })")
                }
                .paperRows()
            }

            Section("stats.per_deck") {
                ForEach(decks) { summary in
                    LabeledContent(summary.deck.name) {
                        Text("deck.due_new \(summary.dueCount) \(summary.newCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .paperRows()
        }
        .screenCanvas()
        .navigationTitle("stats.title")
        .task {
            metrics = await library.metrics(now: Date())
            decks = await library.decks()
        }
    }

    /// "—" rather than a misleading percentage when the sample is too small.
    @ViewBuilder
    private func retention(_ value: Double?) -> some View {
        if let value {
            Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary)
        }
    }
}
