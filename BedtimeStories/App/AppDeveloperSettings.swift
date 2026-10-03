import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

/// UI composition stays outside the app's feature models.
struct AppDeveloperSettings: View {
    let services: AppServices
    @Environment(DeveloperOptions.self) private var options

    var body: some View {
        Section {
            Toggle("Developer Mode", isOn: Binding(get: { options.isEnabled }, set: { enabled in
                AppLog.info("Developer mode changed", category: "developer", metadata: ["enabled": .bool(enabled)])
                options.setEnabled(enabled)
            }))
                .accessibilityIdentifier("developer.mode")
            FoundationSettingsLink(
                services: services,
                pages: FoundationDeveloperTools.pages(services: services)
            )
            if options.isEnabled {
                NavigationLink {
                    AppDeveloperConsole(options: options)
                } label: {
                    Label("Open Logs", systemImage: "terminal")
                }
                .accessibilityIdentifier("developer.logs")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Shake your device to open the logs. Logs stay on this device.")
        }
        .listRowBackground(Theme.surface)
    }
}

private struct AppDeveloperConsole: View {
    let options: DeveloperOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DeveloperConsole(options: options)
            .navigationTitle("Logs")
            .onChange(of: options.isEnabled) { _, enabled in
                if !enabled { dismiss() }
            }
    }
}
