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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .task { await model.start() }
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
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius)
        )
        .padding(.horizontal, Spacing.normal)
        .contentShape(Rectangle())
        .onTapGesture { if !model.isRevealed { model.reveal() } }
    }

    private var revealButton: some View {
        PrimaryActionButton(title: "study.show_answer", subtitle: nil, systemImage: "eye") {
            model.reveal()
        }
        .padding(.horizontal, Spacing.normal)
        .keyboardShortcut(.space, modifiers: [])
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
        }
        ToolbarItem(placement: .primaryAction) {
            Button("study.undo", systemImage: "arrow.uturn.backward") {
                Task { await model.undo() }
            }
            .disabled(!model.canUndo)
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
                .foregroundStyle(.green)
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
    }
}
