import AuthenticationServices
import SwiftUI

struct CloudAccountView: View {
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !cloud.isConfigured || !cloud.isEnabled {
            Section {
                VStack(spacing: 14) {
                    VoiceAvatar(size: 72)
                        .symbolEffect(.variableColor.iterative.reversing)
                    Text("Voice Narration Is Coming").storyFont(.title3, weight: .bold).foregroundStyle(Theme.moonlight)
                        .multilineTextAlignment(.center)
                    Text("Keep writing stories and recording them yourself. Creating a reusable voice will be available here when it is ready.")
                        .font(.subheadline).foregroundStyle(Theme.moonlight.opacity(0.75)).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .background(NightCardBackground())
                .accessibilityElement(children: .combine)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else if cloud.userID == nil {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        VoiceAvatar(size: 48)
                        Text("Your Private Voice").storyFont(.title3, weight: .semibold).foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text("Sign in to keep your voice and generated narration private and use them across your devices.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    SignInWithAppleButton(.signIn, onRequest: cloud.prepareAppleSignIn, onCompletion: cloud.handleAppleSignIn)
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50).clipShape(.capsule)
                        .accessibilityIdentifier("cloud-apple-sign-in")
                        .disabled(cloud.isWorking)
                }
                .padding(.vertical, 8)
            } footer: {
                Text("Your iCloud book library continues to use your Apple Account. Signing in here gives you access to your private saved voices.")
            }
            .listRowBackground(Theme.surface)
        }
    }
}
