import FlashUpDomain
import SwiftUI

/// The `.apkg` mapping stage: one section per Anki note type (spec §A9.5).
///
/// An Anki deck brings its own note types with arbitrary fields, and no heuristic gets that
/// right every time. So the proposal arrives pre-filled and the user confirms it — with a
/// live preview of the first card, because seeing the result is what makes the screen
/// understandable without instructions.
struct FieldMappingView: View {
    @Bindable var model: ImportModel

    var body: some View {
        List {
            Section {
                Text("import.mapping.explanation")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach($model.mappings) { $mapping in
                Section {
                    Toggle("import.mapping.include", isOn: $mapping.isEnabled)
                        .accessibilityIdentifier("import.mapping.include")

                    if mapping.isEnabled {
                        typePicker($mapping)
                        fieldPickers($mapping)
                        preview(mapping)
                    }
                } header: {
                    header(mapping)
                } footer: {
                    if mapping.isEnabled, !mapping.ignoredFieldNames.isEmpty {
                        Text("import.mapping.ignored \(mapping.ignoredFieldNames.formatted(.list(type: .and)))")
                    }
                }
            }

        }
        // Pinned, not the last row: an Anki deck brings one section per note type, so as a
        // row the way forward would sit however far down the deck happens to be long.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.tight) {
                if !model.canContinueFromMapping {
                    Text("import.mapping.nothing_selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryActionButton(
                    title: "import.mapping.continue",
                    subtitle: nil,
                    systemImage: "arrow.right"
                ) {
                    Task { await model.confirmMapping() }
                }
                .disabled(!model.canContinueFromMapping)
                .accessibilityIdentifier("import.mapping.continue")
            }
            .padding(.horizontal, Spacing.loose)
            .padding(.bottom, Spacing.normal)
        }
    }

    // MARK: - Sections

    private func header(_ mapping: FieldMapping) -> some View {
        HStack {
            Text(mapping.noteTypeName)
            Spacer()
            Text("import.mapping.note_count \(mapping.noteCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func typePicker(_ mapping: Binding<FieldMapping>) -> some View {
        Picker("import.mapping.card_type", selection: mapping.target) {
            Text("note_type.basic").tag(NoteType.basic)
            Text("note_type.reversed").tag(NoteType.reversed)
            Text("note_type.cloze").tag(NoteType.cloze)
        }
        .accessibilityIdentifier("import.mapping.type")
    }

    @ViewBuilder
    private func fieldPickers(_ mapping: Binding<FieldMapping>) -> some View {
        let fields = mapping.wrappedValue.fieldNames

        Picker("import.mapping.front_field", selection: mapping.frontIndex) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, name in
                Text(name).tag(index)
            }
        }
        .accessibilityIdentifier("import.mapping.front")

        // A cloze card carries its answer inside the sentence, so its back is an optional
        // extra rather than the answer — offering "none" only makes sense there.
        Picker("import.mapping.back_field", selection: mapping.backIndex) {
            if mapping.wrappedValue.target == .cloze {
                Text("import.mapping.no_back").tag(Int?.none)
            }
            ForEach(Array(fields.enumerated()), id: \.offset) { index, name in
                Text(name).tag(Int?.some(index))
            }
        }
        .accessibilityIdentifier("import.mapping.back")
    }

    /// The whole point of the screen: the change is visible, not described.
    @ViewBuilder
    private func preview(_ mapping: FieldMapping) -> some View {
        if let row = model.previewRow(for: mapping) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("import.mapping.preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(row.front.asNoteSummary)
                    .lineLimit(3)
                if let back = row.back {
                    Text(back.asNoteSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("import.mapping.preview")
        }
    }
}
