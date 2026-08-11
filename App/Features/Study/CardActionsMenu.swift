import SwiftUI

/// The card tools the reviewer offers (spec §A11.3).
///
/// Only sections and buttons, no container: the same body serves the toolbar menu and the
/// long-press menu on the card itself, so the two can never drift apart.
///
/// ```swift
/// Menu { CardActionsMenu(…) } label: { … }
/// .contextMenu { CardActionsMenu(…) }
/// ```
struct CardActionsMenu: View {
    /// Note-level actions are hidden rather than shown dead when the note made one card.
    let hasSiblings: Bool
    let onEdit: () -> Void
    let onInfo: () -> Void
    let onBury: (StudySessionModel.ActionTarget) -> Void
    let onSuspend: (StudySessionModel.ActionTarget) -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Section {
            Button("study.action.edit", systemImage: "pencil", action: onEdit)
                .accessibilityIdentifier("study.action.edit")
            Button("study.action.info", systemImage: "info.circle", action: onInfo)
                .accessibilityIdentifier("study.action.info")
        }

        Section {
            Button("study.action.bury_card", systemImage: "moon.zzz") { onBury(.card) }
                .accessibilityIdentifier("study.action.bury_card")
            Button("study.action.suspend_card", systemImage: "pause.circle") { onSuspend(.card) }
                .accessibilityIdentifier("study.action.suspend_card")

            if hasSiblings {
                Button("study.action.bury_note", systemImage: "moon.zzz.fill") { onBury(.note) }
                    .accessibilityIdentifier("study.action.bury_note")
                Button("study.action.suspend_note", systemImage: "pause.circle.fill") { onSuspend(.note) }
                    .accessibilityIdentifier("study.action.suspend_note")
            }
        }

        Section {
            Button("study.action.reset", systemImage: "arrow.counterclockwise", role: .destructive, action: onReset)
                .accessibilityIdentifier("study.action.reset")
            Button("study.action.delete", systemImage: "trash", role: .destructive, action: onDelete)
                .accessibilityIdentifier("study.action.delete")
        }
    }
}
