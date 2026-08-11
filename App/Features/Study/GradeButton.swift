import FlashUpDomain
import SwiftUI

/// One of the four answers, captioned with the interval it buys.
///
/// The caption is the whole point: the learner grades honestly when they can see what each
/// answer costs them. VoiceOver reads the interval as the button's value.
struct GradeButton: View {
    let grade: Grade
    let interval: TimeInterval?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, Spacing.tight)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(tint)
                    .frame(height: 3)
                    .clipShape(Capsule())
                    .padding(.horizontal, Spacing.normal)
            }
        }
        .buttonStyle(PressableGlassButtonStyle(cornerRadius: Spacing.controlCornerRadius))
        .keyboardShortcut(shortcut, modifiers: [])
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(caption))
        .accessibilityIdentifier("study.grade.\(name)")
    }

    /// Stable, language-independent handle for UI tests and the recording flows. The
    /// localized title cannot serve: it changes with the device language.
    private var name: String {
        switch grade {
        case .again: "again"
        case .hard: "hard"
        case .good: "good"
        case .easy: "easy"
        }
    }

    private var title: LocalizedStringKey {
        switch grade {
        case .again: "grade.again"
        case .hard: "grade.hard"
        case .good: "grade.good"
        case .easy: "grade.easy"
        }
    }

    private var tint: Color {
        switch grade {
        case .again: Palette.destructive
        case .hard: Palette.terracotta
        case .good: Palette.sage
        case .easy: Palette.slate
        }
    }

    /// Keys 1–4, so an iPad with a keyboard grades without leaving the home row.
    private var shortcut: KeyEquivalent {
        switch grade {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }

    /// Compact interval caption: "<10 min", "3 g", "2 mesi".
    private var caption: String {
        guard let interval, interval > 0 else { return "—" }
        return IntervalFormatter.short(interval)
    }
}

/// Formats a next-review interval the way a learner reads it at a glance.
enum IntervalFormatter {
    static func short(_ interval: TimeInterval) -> String {
        let minutes = interval / 60
        if minutes < 60 {
            return String(localized: "interval.minutes \(Int(minutes.rounded()))")
        }
        let hours = minutes / 60
        if hours < 24 {
            return String(localized: "interval.hours \(Int(hours.rounded()))")
        }
        let days = hours / 24
        if days < 30 {
            return String(localized: "interval.days \(Int(days.rounded()))")
        }
        return String(localized: "interval.months \(Int((days / 30).rounded()))")
    }
}
