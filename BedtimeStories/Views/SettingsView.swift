import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(OperationCenter.self) private var operations
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        @Bindable var operations = operations
        Form {
            Section {
                VStack(spacing: 12) {
                    AppGlyph(size: 76)
                    Text("Always Near Stories").storyFont(.title2, weight: .bold).foregroundStyle(Theme.ink)
                    Text("Created by Mateusz Zając").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            Section {
                NavigationLink {
                    OperationsView()
                } label: {
                    HStack {
                        row("Ongoing Operations", systemImage: "sparkles")
                        Spacer()
                        if !operations.activeOperations.isEmpty {
                            Text(operations.activeOperations.count, format: .number)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.accentSoft, in: .capsule)
                        }
                    }
                }
                .accessibilityIdentifier("settings-ongoing-operations")
                Toggle("Completion notifications", isOn: $operations.completionAlertsEnabled)
                    .onChange(of: operations.completionAlertsEnabled) { _, enabled in
                        if enabled { Task { await enableNotifications() } }
                    }
                if operations.completionAlertsEnabled && !operations.notificationsEnabled {
                    Button("Enable Notifications", systemImage: "bell.badge") {
                        Task { await enableNotifications() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } header: { Text("Background Activity") } footer: {
                Text("Follow your stories, voices, and downloads here. Updates appear in the app; notifications let you know when work finishes while you’re away.")
            }
            .listRowBackground(Theme.surface)
            Section {
                LabeledContent {
                    Text(library.cloudStorage ? String(localized: "iCloud Drive") : String(localized: "On This Device"))
                } label: { row("Storage", systemImage: library.cloudStorage ? "icloud.fill" : "iphone") }
                LabeledContent { Text(verbatim: "Always Near Stories / Books") } label: { row("Folder", systemImage: "folder.fill") }
                Text("The app uses its default library automatically. Open Files to manage its books and sharing.").font(.footnote).foregroundStyle(.secondary)
                Button {
                    AppLog.debug("Library setup retry selected", category: "navigation", metadata: ["source": .string("settings")])
                    Task { await library.start() }
                } label: { row("Retry Library Setup", systemImage: "arrow.clockwise", color: Theme.accent) }
                    .disabled(library.activity != nil || library.preparingLibrary)
                if let message = library.migrationMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Library") } footer: {
                Text("iCloud syncs books across your devices using the same Apple Account. Family members need an invitation to a shared folder in Files. Sharing does not automatically connect their app libraries; they can import a shared .bedtimestory file. Reading and listening positions stay on each device.")
            }
            .listRowBackground(Theme.surface)
            Section {
                LabeledContent { Text(library.pinned.count, format: .number) } label: { row("Books Kept Offline", systemImage: "arrow.down.circle.fill") }
                Button {
                    AppLog.debug("Clear Temporary Downloads selected", category: "navigation", metadata: ["kept_offline_count": .integer(library.pinned.count)])
                    library.clearCache()
                } label: { row("Clear Temporary Downloads", systemImage: "trash.fill", color: Theme.accent) }.disabled(library.activity != nil)
            } header: { Text("Downloads") } footer: { Text("Books kept offline and the active recording are preserved.") }
            .listRowBackground(Theme.surface)
            Section {
                row("Keep each book in its own folder, or import a .bedtimestory file. Text, artwork, and audio are optional.", systemImage: "books.vertical.fill")
                row("Use the bedtime-book-create skill in Codex to package your own stories and recordings.", systemImage: "wand.and.stars")
            } header: { Text("Creating Books") }
            .listRowBackground(Theme.surface)
            Section {
                NavigationLink { YourVoicesView() } label: { row("Your Voices", systemImage: "person.wave.2.fill") }
            } header: { Text("Narration") }
            .listRowBackground(Theme.surface)
            Section {
                LabeledContent { Text(verbatim: "1.0") } label: { row("Version", systemImage: "info.circle.fill") }
            }
            .listRowBackground(Theme.surface)
            AppDeveloperSettings(services: MZBootstrap.services)
        }
        .storyFormStyle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, color: Color = Theme.ink) -> some View {
        Label { Text(title).foregroundStyle(color) } icon: { IconTile(systemName: systemImage, size: 30) }
    }

    private func enableNotifications() async {
        await operations.requestNotificationAuthorization()
        guard !operations.notificationsEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// The app's moon-and-hills mark, drawn to match the icon.
struct AppGlyph: View {
    var size: CGFloat = 60
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A3478), Theme.nightBottom], startPoint: .top, endPoint: .bottom)
            Starfield(seed: 0xA11, color: Theme.moonlight, intensity: 0.9)
            CrescentShape()
                .fill(LinearGradient(colors: [Color(hex: 0xFFF6E2), Color(hex: 0xF5C77E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.36, height: size * 0.36)
                .shadow(color: Color(hex: 0xF5C77E).opacity(0.6), radius: size * 0.08)
                .offset(x: size * 0.1, y: -size * 0.12)
            Ellipse().fill(Color(hex: 0x2A2560)).frame(width: size * 1.4, height: size * 0.5).offset(x: -size * 0.25, y: size * 0.42)
            Ellipse().fill(Color(hex: 0x1B1840)).frame(width: size * 1.3, height: size * 0.5).offset(x: size * 0.3, y: size * 0.5)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225))
        .shadow(color: Theme.shadow, radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}
