import FlashUpDomain
import SwiftUI
import UniformTypeIdentifiers

/// Picker → preview → result (spec §A9.2).
///
/// The preview is where trust is won or lost: the user sees exactly what will be created,
/// what is a duplicate, and why a row was refused, before anything is written.
struct ImportFlowView: View {
    let library: any LibraryRepository
    var onFinish: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var model: ImportModel

    init(
        library: any LibraryRepository,
        mediaStore: (any MediaStore)? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        self.library = library
        self.onFinish = onFinish
        _model = State(initialValue: ImportModel(library: library, mediaStore: mediaStore))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .choosing: chooser
                case .mapping: FieldMappingView(model: model)
                case .preview: preview
                case let .done(count): result(count)
                }
            }
            .screenCanvas()
            .navigationTitle(model.stage == .mapping ? "import.mapping.title" : "import.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        onFinish()
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $model.isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .text, .ankiPackage]
        ) { result in
            Task { await model.load(result) }
        }
        .task { await model.prepare() }
    }

    // MARK: - Stages

    private var chooser: some View {
        List {
            Section {
                // First, because it is the end of the journey the prompt card below starts:
                // the assistant replies with text, and text is already on the clipboard.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { await model.loadPasted(text) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Palette.terracotta)
                .accessibilityIdentifier("import.paste")

                Button {
                    model.isPickingFile = true
                } label: {
                    Label("import.pick_file", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("import.pick")

                Button {
                    Task { await model.loadSample() }
                } label: {
                    Label("import.try_sample", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("import.sample")
            } header: {
                Text("import.source")
            } footer: {
                Text("import.format_help")
            }
            .paperRows()

            Section {
                CSVPromptCard()
            }
            .paperRows()

            Section("import.destination") {
                Picker("import.destination", selection: $model.destination) {
                    Text("import.new_deck").tag(ImportModel.Destination.newDeck)
                    ForEach(model.decks) { summary in
                        Text(summary.deck.name).tag(ImportModel.Destination.existing(summary.deck.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if model.destination == .newDeck {
                    TextField("import.new_deck_name", text: $model.newDeckName)
                        .accessibilityIdentifier("import.deck_name")
                }
            }
            .paperRows()

            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(Palette.destructive)
                }
                .paperRows()
            }
        }
    }

    private var preview: some View {
        List {
            Section("import.summary") {
                CountRow(label: "import.will_import", value: model.plan.rowsToImport.count, tint: Palette.successText)
                CountRow(label: "import.duplicates", value: model.plan.duplicates.count, tint: Palette.dueText)
                CountRow(label: "import.rejected", value: model.plan.rejected.count, tint: Palette.destructive)
            }
            .paperRows()

            if !model.plan.valid.isEmpty {
                Section("import.preview_rows") {
                    ForEach(model.plan.valid.prefix(5), id: \.line) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.front.asNoteSummary).lineLimit(1)
                            Text((row.back ?? "").asNoteSummary)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .paperRows()
            }

            if !model.plan.duplicates.isEmpty {
                Section("import.duplicates_section") {
                    ForEach(Array(model.plan.duplicates.enumerated()), id: \.offset) { index, duplicate in
                        Toggle(isOn: Binding(
                            get: { model.plan.duplicates[index].isSelected },
                            set: { model.plan.duplicates[index].isSelected = $0 }
                        )) {
                            Text(duplicate.row.front.asNoteSummary).lineLimit(1)
                        }
                    }
                }
                .paperRows()
            }

            if !model.plan.rejected.isEmpty {
                Section("import.rejected_section") {
                    ForEach(Array(model.plan.rejected.enumerated()), id: \.offset) { _, rejection in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.isApkg
                                ? "import.note \(rejection.line)"
                                : "import.row \(rejection.line)")
                                .font(.caption.weight(.semibold))
                            Text(reason(rejection.reason)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .paperRows()
            }

            Section {
                Button("import.confirm") {
                    Task { await model.commit() }
                }
                .disabled(model.plan.isEmpty)
                .accessibilityIdentifier("import.confirm")
            }
            .paperRows()
        }
    }

    private func result(_ count: Int) -> some View {
        VStack(spacing: Spacing.loose) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.successText)
            Text("import.done.title")
                .font(.title3.weight(.semibold))
            Text("import.done.count \(count)")
                .foregroundStyle(.secondary)

            Button("import.undo") {
                Task { await model.undo() }
            }
            .accessibilityIdentifier("import.undo")

            PrimaryActionButton(title: "import.done.close", subtitle: nil, systemImage: "checkmark") {
                onFinish()
                dismiss()
            }
            .padding(.horizontal, Spacing.loose)
            Spacer()
        }
        .padding(Spacing.loose)
    }

    private func reason(_ reason: RowRejection.Reason) -> LocalizedStringKey {
        switch reason {
        case let .unknownType(value): "import.reason.type \(value)"
        case .emptyFront: "import.reason.front"
        case .missingBack: "import.reason.back"
        case .noClozeDeletion: "import.reason.cloze"
        case let .fieldTooLong(column, characters): "import.reason.long \(column) \(characters)"
        case let .unsupportedMedia(filename): "import.reason.media \(filename)"
        }
    }
}

private struct CountRow: View {
    let label: LocalizedStringKey
    let value: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .number)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
