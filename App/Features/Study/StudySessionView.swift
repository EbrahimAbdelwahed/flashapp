import FlashUpDomain
import SwiftUI

/// The screen the product lives in (spec §A11.3).
///
/// Prompt, then a tap anywhere reveals the answer, then four grades captioned with the
/// interval each one buys. The card text sits on an opaque surface, never over glass, so it
/// stays legible (`docs/ux-principles.md` §1).
struct StudySessionView: View {
    let library: any LibraryRepository
    let scope: StudyScope

    @State private var model: StudySessionModel
    @State private var editingNote: Note?
    @State private var cardInfo: CardInfo?
    @State private var isConfirmingReset = false
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(library: any LibraryRepository, scope: StudyScope) {
        self.library = library
        self.scope = scope
        _model = State(initialValue: StudySessionModel(library: library, scope: scope))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isFinished {
                    SessionCompleteView(answered: model.answeredCount) { dismiss() }
                } else {
                    session
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $editingNote) { note in
                NoteEditorView(library: library, deckID: note.deckID, note: note) {
                    Task { await model.refreshAfterEdit() }
                }
            }
            .sheet(item: $cardInfo) { info in
                CardInfoView(info: info) { cardInfo = nil }
            }
            .confirmationDialog(
                "study.action.reset.confirm",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("study.action.reset", role: .destructive) {
                    Task { await model.resetCurrentCard() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("study.action.reset.message")
            }
            .confirmationDialog(
                "study.action.delete.confirm",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("study.action.delete", role: .destructive) {
                    Task { await model.deleteCurrentNote() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("study.action.delete.message")
            }
            .alert(
                "study.error.title",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.clearError() } }
                )
            ) {
                Button("common.ok") { model.clearError() }
            } message: {
                Text(model.errorMessage ?? "study.error.unavailable")
            }
        }
        .task { await model.start() }
    }

    /// The card tools, wired once and handed to both the toolbar and the long-press menu.
    private var cardActions: CardActionsMenu {
        CardActionsMenu(
            hasSiblings: model.hasSiblings,
            onEdit: { Task { editingNote = await model.currentNote() } },
            onInfo: { Task { cardInfo = await model.currentCardInfo() } },
            onBury: { target in Task { await model.bury(target) } },
            onSuspend: { target in Task { await model.suspend(target) } },
            onReset: { isConfirmingReset = true },
            onDelete: { isConfirmingDelete = true }
        )
    }

    // MARK: - Session

    private var session: some View {
        VStack(spacing: Spacing.normal) {
            ProgressView(value: model.progress)
                .padding(.horizontal, Spacing.normal)
                .accessibilityLabel("study.progress")
                .accessibilityValue(Text("study.remaining \(model.remaining)"))

            card

            if model.isRevealed {
                grades
                    .transition(.opacity)
            } else {
                revealButton
            }
        }
        .padding(.bottom, Spacing.normal)
        .animation(Motion.reveal(reduceMotion: reduceMotion), value: model.isRevealed)
    }

    private var card: some View {
        ScrollView {
            if let current = model.current {
                CardFaceView(card: current, isRevealed: model.isRevealed)
                    .padding(Spacing.loose)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque, not glass: study text must never fight a blurred background.
        .background(
            Palette.paper,
            in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius)
        )
        .padding(.horizontal, Spacing.normal)
        .contentShape(Rectangle())
        .onTapGesture { if !model.isRevealed { model.reveal() } }
        .contextMenu { cardActions }
        .accessibilityIdentifier("study.card")
    }

    private var revealButton: some View {
        PrimaryActionButton(title: "study.show_answer", subtitle: nil, systemImage: "eye") {
            model.reveal()
        }
        .padding(.horizontal, Spacing.normal)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityIdentifier("study.reveal")
    }

    private var grades: some View {
        HStack(spacing: Spacing.tight) {
            ForEach(Grade.allCases, id: \.rawValue) { grade in
                GradeButton(grade: grade, interval: model.interval(for: grade)) {
                    Task { await model.answer(grade) }
                }
            }
        }
        .padding(.horizontal, Spacing.normal)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("study.close") { dismiss() }
                .accessibilityIdentifier("study.close")
        }
        // Undo stays a single tap: it is the high-frequency action and does not belong
        // behind a menu. The rest live together under one affordance.
        ToolbarItemGroup(placement: .primaryAction) {
            Button("study.undo", systemImage: "arrow.uturn.backward") {
                Task { await model.undo() }
            }
            .disabled(!model.canUndo)
            .accessibilityIdentifier("study.undo")

            Menu {
                cardActions
            } label: {
                Label("common.more", systemImage: "ellipsis.circle")
            }
            .disabled(model.isFinished)
            .accessibilityIdentifier("study.actions")
        }
    }
}

/// Shown when the queue empties.
struct SessionCompleteView: View {
    let answered: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Spacing.loose) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Palette.successText)
            Text("study.complete.title")
                .font(.title2.weight(.semibold))
            Text("study.complete.count \(answered)")
                .foregroundStyle(.secondary)

            PrimaryActionButton(title: "study.complete.done", subtitle: nil, systemImage: "house") {
                onDone()
            }
            .padding(.horizontal, Spacing.loose)
        }
        .padding(Spacing.loose)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.complete")
    }
}
