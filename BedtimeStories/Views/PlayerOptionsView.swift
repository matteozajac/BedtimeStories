import SwiftUI
import AVKit

struct PlayerOptionsView: View {
    @Environment(LibraryModel.self) private var library
    var body: some View {
        let sleeping = library.player.sleepLabel != nil
        HStack(spacing: 12) {
            Menu {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { speed in
                    Button("\(speed.formatted())×") { library.player.setSpeed(speed) }
                }
            } label: {
                Text("\(library.player.speed.formatted())×").font(.subheadline.weight(.bold)).monospacedDigit()
                    .frame(minWidth: 64, minHeight: 44).glassEffect(.regular.interactive(), in: .capsule)
            }
            .accessibilityLabel("Playback speed")
            Spacer(minLength: 0)
            AirPlayButton().frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("AirPlay")
            Spacer(minLength: 0)
            Menu {
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { library.player.setSleep(minutes: minutes) }
                }
                Button("End of chapter", action: library.player.sleepAtChapterEnd).disabled(!library.player.canSleepAtChapterEnd)
                Button("Turn Off", action: library.player.cancelSleep)
            } label: {
                Label(library.player.sleepLabel ?? String(localized: "Sleep Timer"), systemImage: sleeping ? "moon.zzz.fill" : "moon.zzz")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(sleeping ? Color(hex: 0x1F1830) : Theme.accent)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(sleeping ? Theme.accent : .clear, in: .capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }
}
