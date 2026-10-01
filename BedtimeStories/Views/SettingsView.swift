import SwiftUI

struct SettingsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                LabeledContent("Folder", value: library.root?.lastPathComponent ?? String(localized: "Not selected"))
                Text("Open Files to manage this folder and its sharing.").font(.footnote).foregroundStyle(.secondary)
                Button("Change Library Folder", systemImage: "folder") { dismiss(); library.showingFolderPicker = true }.disabled(library.activity != nil)
            } header: { Text("Library Folder") } footer: { Text("Share your iCloud Drive folder with family in Files. Listening and reading positions are saved separately on each device.") }
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
