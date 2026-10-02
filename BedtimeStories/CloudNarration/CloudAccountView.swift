import AuthenticationServices
import SwiftUI

struct CloudAccountView: View {
    @Environment(CloudNarrationModel.self) private var cloud

    var body: some View {
        if !cloud.isConfigured || !cloud.isEnabled {
            ContentUnavailableView {
                Label("Voice Narration Is Coming", systemImage: "waveform")
            } description: {
                Text("Keep writing stories and recording them yourself. Creating a reusable voice will be available here when it is ready.")
            }
        } else if cloud.userID == nil {
            Section {
                Text("Sign in to keep your voice and generated narration private and use them across your devices.")
                SignInWithAppleButton(.signIn, onRequest: cloud.prepareAppleSignIn, onCompletion: cloud.handleAppleSignIn)
                    .frame(minHeight: 50).clipShape(.rect(cornerRadius: 10))
                    .accessibilityIdentifier("cloud-apple-sign-in")
                    .disabled(cloud.isWorking)
            } header: { Text("Your Private Voice") } footer: {
                Text("Your iCloud book library continues to use your Apple Account. Signing in here gives you access to your private saved voices.")
            }
        }
    }
}
