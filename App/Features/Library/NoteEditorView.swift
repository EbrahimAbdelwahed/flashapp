import FlashUpDomain
import SwiftUI

/// Creates or edits a note, showing live which cards it will generate.
///
/// The preview is the teaching device: the user sees immediately that a reversed note makes
/// two cards and that each cloze group makes its own, so the note types never need a manual.
struct NoteEditorView: View {
    let library: any LibraryRepository
    let deckID: UUID
    let note: Note?
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoteDraft
    @State private var tagText: String

    init(library: any LibraryRepository, deckID: UUID, note: Note?, onSave: @escaping () -> Void = {}) {
        self.library = library
        self.deckID = deckID
        self.note = note
        self.onSave = onSave
        let initial = note.map(NoteDraft.init) ?? NoteDraft(deckID: deckID, type: .basic, front: "", back: "")
        _draft = State(initialValue: initial)
        _tagText = State(initialValue: (note?.tags ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("editor.type", selection: $draft.type) {
                        ForEach(NoteType.allCases, id: \.self) { type in
                            Text(typeTitle(type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor.type")
                } footer: {
                    Text(typeHelp(draft.type))
                }
                .paperRows()

                Section("editor.front") {
                    TextEditor(text: $draft.front)
                        .frame(minHeight: 90)
                        .accessibilityIdentifier("editor.front")
                }
                .paperRows()

                Section("editor.back") {
                    TextEditor(text: Binding(
                        get: { draft.back ?? "" },
                        set: { draft.back = $0 }
                    ))
                    .frame(minHeight: 70)
                    .accessibilityIdentifier("editor.back")
                }
                .paperRows()

                Section("editor.tags") {
                    TextField("editor.tags_placeholder", text: $tagText)
                        .accessibilityIdentifier("editor.tags")
                }
                .paperRows()

                cardPreview
            }
            .screenCanvas()
            .navigationTitle(note == nil ? "editor.new_title" : "editor.edit_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("editor.save")
                }
            }
        }
    }

    /// Live view of the cards this note will produce.
    private var cardPreview: some View {
        Section("editor.preview") {
            let previews = CardGenerator.generate(previewNote)
            if previews.isEmpty {
                Text("editor.preview_empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(previews, id: \.templateKey) { template in
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.templateKey)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(template.front).font(.subheadline)
                    Text(template.back)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .paperRows()
    }

    private var previewNote: Note {
        Note(deckID: deckID, type: draft.type, front: draft.front, back: draft.back, tags: [])
    }

    private func save() {
        var toSave = draft
        toSave.deckID = deckID
        toSave.tags = tagText.split(separator: ",").map(String.init)
        Task {
            await library.saveNote(toSave)
            onSave()
            dismiss()
        }
    }

    private func typeTitle(_ type: NoteType) -> LocalizedStringKey {
        switch type {
        case .basic: "note_type.basic"
        case .reversed: "note_type.reversed"
        case .cloze: "note_type.cloze"
        }
    }

    private func typeHelp(_ type: NoteType) -> LocalizedStringKey {
        switch type {
        case .basic: "note_type.basic.help"
        case .reversed: "note_type.reversed.help"
        case .cloze: "note_type.cloze.help"
        }
    }
}
