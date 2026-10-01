import SwiftUI
import AVKit

struct PlayerOptionsView: View {
    @Environment(LibraryModel.self) private var library
    var body: some View {
        HStack {
            Menu {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { speed in
                    Button("\(speed.formatted())×") { library.player.setSpeed(speed) }
                }
            } label: { Text("\(library.player.speed.formatted())×").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Playback speed")
            Spacer()
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            Spacer()
            Menu {
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { library.player.setSleep(minutes: minutes) }
                }
                Button("End of chapter", action: library.player.sleepAtChapterEnd).disabled(!library.player.canSleepAtChapterEnd)
                Button("Turn Off", action: library.player.cancelSleep)
            } label: {
                Label(library.player.sleepLabel ?? String(localized: "Sleep Timer"), systemImage: "moon.zzz").font(.subheadline).frame(minHeight: 44)
            }
        }
    }
}
