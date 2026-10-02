import SwiftUI
import UIKit

/// Shared colors and type for the storybook look: warm paper by day, a calm
/// midnight sky by night. Story content is set in a serif; app chrome is rounded.
enum Theme {
    /// Twilight plum by day, lamplight honey by night.
    static let accent = Color(light: 0x5B4B9A, dark: 0xF2B65E)
    static let onAccent = Color(light: 0xFFFBF4, dark: 0x1F1830)
    /// A quiet fill behind accent-colored icons and secondary buttons.
    static let accentSoft = Color(light: UIColor(hex: 0x5B4B9A, alpha: 0.11), dark: UIColor(hex: 0xFFE7C2, alpha: 0.11))
    /// Moon, stars and other warm highlights.
    static let glow = Color(light: 0xE39B45, dark: 0xF5C77E)
    static let ink = Color(light: 0x2B2440, dark: 0xF1E9DA)
    static let paperTop = Color(light: 0xFCF7EF, dark: 0x1A1C36)
    static let paperBottom = Color(light: 0xF3EDF4, dark: 0x0E1023)
    static let surface = Color(light: UIColor(white: 1, alpha: 0.78), dark: UIColor(white: 1, alpha: 0.07))
    static let surfaceStroke = Color(light: UIColor(hex: 0x5B4B9A, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.08))
    static let shadow = Color(light: UIColor(hex: 0x2B2440, alpha: 0.16), dark: UIColor(white: 0, alpha: 0.45))
    static let recording = Color(light: 0xD9534F, dark: 0xFF7A70)

    /// The night sky used behind the player and the welcome screen in every appearance.
    static let nightTop = Color(hex: 0x1D2042)
    static let nightBottom = Color(hex: 0x0B0D1E)
    static let moonlight = Color(hex: 0xF7E9CC)

    static func applyNavigationBarAppearance() {
        let bar = UINavigationBar.appearance()
        let ink = UIColor(Theme.ink)
        if let descriptor = UIFont.preferredFont(forTextStyle: .largeTitle).fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) {
            bar.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0), .foregroundColor: ink]
        }
        if let descriptor = UIFont.preferredFont(forTextStyle: .headline).fontDescriptor.withDesign(.rounded) {
            bar.titleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0), .foregroundColor: ink]
        }
    }
}

extension View {
    /// Serif type for stories, titles, and other content. The design is applied
    /// here so it wins over the rounded design used for the rest of the app.
    func storyFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        font(.system(style, weight: weight)).fontDesign(.serif)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
