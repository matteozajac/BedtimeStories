import SwiftUI

struct SettingsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                LabeledContent("Storage", value: library.cloudStorage ? String(localized: "iCloud Drive") : String(localized: "On This Device"))
                LabeledContent("Folder", value: "Always Near Stories / Books")
                Text("The app uses its default library automatically. Open Files to manage its books and sharing.").font(.footnote).foregroundStyle(.secondary)
                Button("Retry Library Setup", systemImage: "arrow.clockwise") { Task { await library.start() } }
                    .disabled(library.activity != nil || library.preparingLibrary)
                if let message = library.migrationMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Library") } footer: {
                Text("iCloud syncs books across your devices using the same Apple Account. Family members need an invitation to a shared folder in Files. Sharing does not automatically connect their app libraries; they can import a shared .bedtimestory file. Reading and listening positions stay on each device.")
            }
            Section {
                LabeledContent("Books Kept Offline", value: "\(library.pinned.count)")
                Button("Clear Temporary Downloads", systemImage: "trash", action: library.clearCache).disabled(library.activity != nil)
            } header: { Text("Downloads") } footer: { Text("Books kept offline and the active recording are preserved.") }
            Section("Creating Books") {
                Text("Keep each book in its own folder, or import a .bedtimestory file. Text, artwork, and audio are optional.")
                Text("Use the bedtime-book-create skill in Codex to package your own stories and recordings.")
            }
            Section {
                LabeledContent("Version", value: "1.0")
                Text("Created by Mateusz Zając").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
