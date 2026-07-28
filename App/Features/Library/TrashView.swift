import FlashUpDomain
import SwiftUI

/// Recoverable deletions (spec §A2): nothing the user removes disappears immediately.
struct TrashView: View {
    let library: any LibraryRepository

    @State private var notes: [Note] = []
    @State private var isConfirmingEmpty = false

    var body: some View {
        List {
            if notes.isEmpty {
                EmptyStateRow(
                    title: "trash.empty.title",
                    message: "trash.empty.message",
                    systemImage: "trash"
                )
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.front).lineLimit(2)
                    Text("trash.restorable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("trash.row")
                .swipeActions {
                    Button("trash.restore") {
                        Task {
                            await library.restoreNote(note.id)
                            await reload()
                        }
                    }
                    .tint(.green)
                    .accessibilityIdentifier("trash.restore")
                }
            }
        }
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
                    await library.emptyTrash()
                    await reload()
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("trash.confirm.message")
        }
        .task { await reload() }
    }

    private func reload() async {
        notes = await library.trashedNotes()
    }
}

/// Exports a deck (or the whole library) as the canonical CSV.
struct ExportSheet: View {
    let library: any LibraryRepository
    let deckID: UUID?
    let deckName: String

    @Environment(\.dismiss) private var dismiss
    @State private var exported: ExportedFile?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.loose) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
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
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .padding(Spacing.loose)
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
        let data = await library.exportCSV(deckID: deckID)
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
