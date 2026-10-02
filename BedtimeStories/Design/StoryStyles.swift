import SwiftUI

/// A large, friendly capsule for the main action on a screen.
struct StoryProminentButtonStyle: ButtonStyle {
    var fullWidth = false
    var color = Theme.accent
    var labelColor = Theme.onAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 26)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 56)
            .background {
                Capsule().fill(color)
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)))
            }
            .shadow(color: color.opacity(isEnabled ? 0.28 : 0), radius: 14, y: 6)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A softly tinted capsule for secondary actions.
struct StorySoftButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 56)
            .background(Theme.accentSoft, in: .capsule)
            .overlay(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.08 : 0)))
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Gives books and cards a gentle squish when tapped.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.45), value: configuration.isPressed)
    }
}

/// Places the icon after the title, for forward-moving actions like "Continue".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

/// A tight icon-and-title pair for small metadata, like "Text" or "Picture".
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

extension ButtonStyle where Self == StoryProminentButtonStyle {
    static var storyProminent: Self { .init() }
    static func storyProminent(fullWidth: Bool) -> Self { .init(fullWidth: fullWidth) }
    /// The coral variant used for starting and finishing a recording.
    static var storyRecord: Self { .init(fullWidth: true, color: Theme.recording, labelColor: .white) }
}

extension ButtonStyle where Self == StorySoftButtonStyle {
    static var storySoft: Self { .init() }
    static func storySoft(fullWidth: Bool) -> Self { .init(fullWidth: fullWidth) }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: Self { .init() }
}

extension View {
    /// A rounded, softly outlined container that sits on the story background.
    func storyCard(padding: CGFloat = 20, cornerRadius: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.surfaceStroke))
    }
}

/// A short, spaced-out label above a title, like "Chapter 2 of 5".
struct Eyebrow: View {
    let text: Text
    var color: Color = Theme.accent
    init(_ text: Text, color: Color = Theme.accent) { self.text = text; self.color = color }
    init(_ key: LocalizedStringKey, color: Color = Theme.accent) { self.text = Text(key); self.color = color }

    var body: some View {
        text.font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.2).foregroundStyle(color)
    }
}

/// A small sparkle between two hairlines, used to separate story sections.
struct StoryOrnament: View {
    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(Theme.glow.opacity(0.45)).frame(width: 28, height: 1.5)
            Image(systemName: "sparkle").font(.caption).foregroundStyle(Theme.glow)
            Capsule().fill(Theme.glow.opacity(0.45)).frame(width: 28, height: 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// An icon on a softly colored tile, used in lists and settings.
struct IconTile: View {
    let systemName: String
    var color: Color = Theme.accent
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// A gentle note for library status messages.
struct NoteCard<Actions: View>: View {
    let systemImage: String
    let text: Text
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemName: systemImage, color: Theme.glow, size: 34)
            VStack(alignment: .leading, spacing: 10) {
                text.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                actions.font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .storyCard(padding: 16, cornerRadius: 20)
    }
}

extension NoteCard where Actions == EmptyView {
    init(systemImage: String, text: Text) { self.init(systemImage: systemImage, text: text) { EmptyView() } }
}
