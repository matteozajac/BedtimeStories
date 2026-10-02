import SwiftUI

/// The quiet backdrop behind every screen: paper by day, a soft sky by night,
/// with faint stars and a warm moon glow. Reading pages keep only the paper.
struct StoryBackground: View {
    enum Style { case standard, reading, night }
    var style: Style = .standard
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if style == .night {
                LinearGradient(colors: [Theme.nightTop, Theme.nightBottom], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Theme.paperTop, Theme.paperBottom], startPoint: .top, endPoint: .bottom)
            }
            RadialGradient(colors: [(style == .night ? Theme.moonlight : Theme.glow).opacity(glowOpacity), .clear],
                           center: UnitPoint(x: 0.9, y: -0.04), startRadius: 0, endRadius: 480)
            if style != .reading {
                Starfield(color: dark ? Theme.moonlight : Theme.accent, intensity: dark ? 0.6 : 0.14, twinkles: style == .night)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var dark: Bool { style == .night || colorScheme == .dark }
    private var glowOpacity: Double {
        switch style {
        case .reading: dark ? 0.05 : 0.08
        case .standard: dark ? 0.11 : 0.15
        case .night: 0.13
        }
    }
}

/// Small deterministic stars, densest at the top like a night sky.
struct Starfield: View {
    var seed: UInt64 = 0x5EED
    var color: Color = Theme.moonlight
    var intensity = 1.0
    var twinkles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if twinkles && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
                stars(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            stars(time: nil)
        }
    }

    private func stars(time: Double?) -> some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: seed)
            let count = min(150, max(24, Int(size.width * size.height / 8_500)))
            for index in 0..<count {
                let x = Double.random(in: 0...1, using: &generator)
                let y = pow(Double.random(in: 0...1, using: &generator), 1.5) * 0.72
                let radius = Double.random(in: 0.5...1.4, using: &generator)
                let phase = Double.random(in: 0...(2 * .pi), using: &generator)
                let speed = Double.random(in: 0.35...1.0, using: &generator)
                var alpha = (1 - y / 0.78) * Double.random(in: 0.3...1, using: &generator) * intensity
                if let time { alpha *= 0.6 + 0.4 * sin(time * speed + phase) }
                let point = CGPoint(x: x * size.width, y: y * size.height)
                let shape = index % 11 == 0
                    ? Self.sparkle(center: point, radius: radius * 3.2)
                    : Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(shape, with: .color(color.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }

    static func sparkle(center: CGPoint, radius: CGFloat) -> Path {
        let inner = radius * 0.22
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + inner, y: center.y - inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - inner, y: center.y - inner))
        return path
    }
}

extension View {
    /// Lets a form or list sit on the story background with soft, warm rows.
    func storyFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background { StoryBackground() }
    }
}
