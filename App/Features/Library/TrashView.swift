import FlashUpDomain
import SwiftUI

/// Recoverable deletions (spec §A2): nothing the user removes disappears immediately.
struct TrashView: View {
    let library: any LibraryRepository

    @State private var notes: [Note] = []
    @State private var isConfirmingEmpty = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if notes.isEmpty {
                EmptyStateRow(
                    title: "trash.empty.title",
                    message: "trash.empty.message",
                    systemImage: "trash"
                )
                .paperRows()
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.front.asNoteSummary).lineLimit(2)
                    Text("trash.restorable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("trash.row")
                .swipeActions {
                    Button("trash.restore") {
                        Task {
                            do {
                                try await library.restoreNote(note.id)
                            } catch {
                                errorMessage = String(localized: "storage.error.unavailable")
                                return
                            }
                            await reload()
                        }
                    }
                    .tint(Palette.success)
                    .accessibilityIdentifier("trash.restore")
                }
                .paperRows()
            }
        }
        .screenCanvas()
        .navigationTitle("library.trash_title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("trash.empty_action", role: .destructive) { isConfirmingEmpty = true }
                    .disabled(notes.isEmpty)
                    .accessibilityIdentifier("trash.empty")
            }
        }
        .confirmationDialog(
            "trash.confirm.title",
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("trash.confirm.action", role: .destructive) {
                Task {
                    do {
                        try await library.emptyTrash()
                    } catch {
                        errorMessage = String(localized: "storage.error.unavailable")
                        return
                    }
                    await reload()
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("trash.confirm.message")
        }
        .alert(
            "trash.error.title",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "storage.error.unavailable")
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            notes = try await library.trashedNotes()
        } catch {
            errorMessage = String(localized: "storage.error.unavailable")
        }
    }
}

/// Exports a deck (or the whole library) as the canonical CSV.
struct ExportSheet: View {
    let library: any LibraryRepository
    let deckID: UUID?
    let deckName: String

    @Environment(\.dismiss) private var dismiss
    @State private var exported: ExportedFile?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.loose) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.newText)
                Text("export.title")
                    .font(.title3.weight(.semibold))
                Text("export.message \(deckName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let exported {
                    ShareLink(item: exported.url) {
                        Label("export.share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export.share")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .padding(Spacing.loose)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("export.nav_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        let data: Data
        do {
            data = try await library.exportCSV(deckID: deckID)
        } catch {
            errorMessage = String(localized: "storage.error.unavailable")
            return
        }
        let name = deckName.isEmpty ? "flashup" : deckName
        exported = ExportedFile.write(data, named: "\(name).csv")
    }
}

/// A file written to a temporary location so it can be shared.
struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }

    static func write(_ data: Data, named name: String) -> ExportedFile? {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: safeName)
        do {
            try data.write(to: url, options: .atomic)
            return ExportedFile(url: url)
        } catch {
            return nil
        }
    }
}
