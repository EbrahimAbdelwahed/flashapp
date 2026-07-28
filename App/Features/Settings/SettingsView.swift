import FlashUpDomain
import SwiftUI

/// Settings, and the host for backup, data and support (spec §A11.2).
struct SettingsView: View {
    let library: any LibraryRepository
    let reminders: any ReminderScheduling

    @State private var settings: StudySettings = .default
    @State private var status: SyncStatus = .upToDate(lastSyncedAt: nil)
    @State private var isConfirmingErase = false
    @State private var isRestoring = false
    @State private var backupFile: ExportedFile?
    @State private var restoreSummary: RestoreSummary?
    /// Set when the reminder is on but iOS will not deliver it.
    @State private var isNotificationPermissionMissing = false

    var body: some View {
        List {
            syncSection
            studySection
            reminderSection
            appearanceSection
            dataSection
            aboutSection
        }
        .navigationTitle("tab.settings")
        .task { await reload() }
        .onChange(of: settings) { previous, updated in
            // The reminder toggle persists itself, because it also has to report back what
            // the system granted.
            guard previous.reminder == updated.reminder else { return }
            Task { await library.updateSettings(updated) }
        }
        .fileImporter(isPresented: $isRestoring, allowedContentTypes: [.json, .data]) { result in
            Task { await restore(result) }
        }
        .alert("settings.restore.done", isPresented: .constant(restoreSummary != nil)) {
            Button("common.ok") { restoreSummary = nil }
        } message: {
            if let restoreSummary {
                Text(
                    "settings.restore.summary \(restoreSummary.decksAdded) "
                        + "\(restoreSummary.notesAdded) \(restoreSummary.notesSkipped)"
                )
            }
        }
        .confirmationDialog(
            "settings.erase.title",
            isPresented: $isConfirmingErase,
            titleVisibility: .visible
        ) {
            Button("settings.erase.action", role: .destructive) {
                Task {
                    await library.deleteAllData()
                    await reload()
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.erase.message")
        }
    }

    // MARK: - Sections

    private var syncSection: some View {
        Section("settings.sync") {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.body)
                    Text("settings.sync.explanation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var studySection: some View {
        Section {
            Stepper(value: $settings.newPerDay, in: 0...200, step: 5) {
                LabeledContent("settings.new_per_day") {
                    Text(settings.newPerDay, format: .number).monospacedDigit()
                }
            }
            .accessibilityIdentifier("settings.new_per_day")

            Stepper(value: $settings.reviewsPerDay, in: 10...999, step: 10) {
                LabeledContent("settings.reviews_per_day") {
                    Text(settings.reviewsPerDay, format: .number).monospacedDigit()
                }
            }
            .accessibilityIdentifier("settings.reviews_per_day")
        } header: {
            Text("settings.study")
        } footer: {
            Text("settings.study.help")
        }
    }

    private var reminderSection: some View {
        Section("settings.reminder") {
            Toggle("settings.reminder.enabled", isOn: Binding(
                get: { settings.reminder.isEnabled },
                set: { isOn in
                    var updated = settings
                    updated.reminder.isEnabled = isOn
                    settings = updated
                    Task { await persist(updated) }
                }
            ))
            .accessibilityIdentifier("settings.reminder")
            if isNotificationPermissionMissing {
                Label("settings.reminder.blocked", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.reminder.blocked")
            }

            if settings.reminder.isEnabled {
                DatePicker(
                    "settings.reminder.time",
                    selection: Binding(
                        get: {
                            Calendar.current.date(
                                bySettingHour: settings.reminder.hour,
                                minute: settings.reminder.minute,
                                second: 0,
                                of: Date()
                            ) ?? Date()
                        },
                        set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            settings.reminder.hour = parts.hour ?? 20
                            settings.reminder.minute = parts.minute ?? 30
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section("settings.appearance") {
            Picker("settings.appearance", selection: $settings.appearance) {
                Text("settings.appearance.system").tag(StudySettings.Appearance.system)
                Text("settings.appearance.light").tag(StudySettings.Appearance.light)
                Text("settings.appearance.dark").tag(StudySettings.Appearance.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("settings.appearance")
        }
    }

    private var dataSection: some View {
        Section("settings.data") {
            Button {
                Task { await makeBackup() }
            } label: {
                Label("settings.backup", systemImage: "externaldrive.badge.timemachine")
            }
            .accessibilityIdentifier("settings.backup")

            if let backupFile {
                ShareLink(item: backupFile.url) {
                    Label("settings.backup.share", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                isRestoring = true
            } label: {
                Label("settings.restore", systemImage: "arrow.clockwise")
            }

            NavigationLink {
                TrashView(library: library)
            } label: {
                Label("library.trash_title", systemImage: "trash")
                    .accessibilityIdentifier("settings.trash")
            }

            Button(role: .destructive) {
                isConfirmingErase = true
            } label: {
                Label("settings.erase", systemImage: "exclamationmark.triangle")
            }
            .accessibilityIdentifier("settings.erase")
        }
    }

    private var aboutSection: some View {
        Section("settings.about") {
            NavigationLink {
                HelpView()
            } label: {
                Label("settings.help", systemImage: "questionmark.circle")
            }
            NavigationLink {
                PrivacyView()
            } label: {
                Label("settings.privacy", systemImage: "hand.raised")
            }
            LabeledContent("settings.version") {
                Text(AppInfo.versionString)
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        settings = await library.settings()
        status = await library.syncStatus()
    }

    /// Saves the settings and reflects what the system actually granted: if notification
    /// permission is refused, the switch goes back off instead of promising a reminder that
    /// will never arrive.
    /// Saves the choice, then reports whether iOS will actually deliver it. The switch is
    /// never moved behind the user's back.
    private func persist(_ updated: StudySettings) async {
        await library.updateSettings(updated)
        let scheduled = await reminders.apply(updated.reminder)
        isNotificationPermissionMissing = updated.reminder.isEnabled && !scheduled
    }

    private func makeBackup() async {
        let document = await library.backupDocument(appVersion: AppInfo.versionString, now: Date())
        guard let data = try? BackupCodec.encode(document) else { return }
        backupFile = ExportedFile.write(data, named: "FlashUp.flashupbackup")
    }

    private func restore(_ result: Result<URL, Error>) async {
        guard case let .success(url) = result else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let document = try? BackupCodec.decode(data)
        else { return }
        restoreSummary = await library.restore(document)
        await reload()
    }

    private var statusTitle: LocalizedStringKey {
        switch status {
        case .syncing: "sync.syncing"
        case .upToDate: "sync.up_to_date"
        case .offline: "sync.offline"
        case .accountUnavailable: "sync.no_account"
        case .failed: "sync.failed"
        }
    }

    private var statusIcon: String {
        switch status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .upToDate: "checkmark.icloud"
        case .offline: "icloud.slash"
        case .accountUnavailable: "person.crop.circle.badge.exclamationmark"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var statusTint: Color {
        switch status {
        case .syncing, .upToDate: .green
        case .offline, .accountUnavailable: .secondary
        case .failed: .red
        }
    }
}

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
