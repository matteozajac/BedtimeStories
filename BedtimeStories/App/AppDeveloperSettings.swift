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
                pages: FoundationDeveloperTools.pages(services: services, reporting: MZBootstrap.reporting)
            )
            FoundationKeyboardShortcutsLink(options: options)
            if options.isEnabled {
                Button {
                    options.requestConsole()
                } label: {
                    Label("Open Logs", systemImage: "terminal")
                }
                .accessibilityIdentifier("developer.logs")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Shake your device or press Command-D to open the logs and send a bug report. Logs stay on this device until you share them.")
        }
        .listRowBackground(Theme.surface)
    }
}
