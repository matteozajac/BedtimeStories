import SwiftUI

/// An illustrated cover for books without artwork: an evening sky, a moon,
/// a few stars and rolling hills, in colors chosen from the book's identity.
struct CoverArtwork: View {
    let id: UUID
    var title: String?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let palette = StoryPalette(for: id)
            ZStack {
                Canvas { context, size in Self.draw(palette, in: &context, size: size) }
                if let title, size.width > 90 {
                    Text(title)
                        .font(.system(size: max(13, size.width * 0.105), weight: .bold)).fontDesign(.serif)
                        .foregroundStyle(Color(hex: 0xFFF8EC))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(.horizontal, size.width * 0.12)
                        .frame(width: size.width, height: size.height * 0.5)
                        .position(x: size.width / 2, y: size.height * 0.48)
                }
            }
        }
    }

    private static func draw(_ palette: StoryPalette, in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .linearGradient(Gradient(colors: [palette.skyTop, palette.skyBottom]),
                                                         startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
        var generator = SeededGenerator(seed: palette.seed)

        if size.width > 70 {
            for index in 0..<16 {
                let point = CGPoint(x: .random(in: 0.06...0.94, using: &generator) * size.width,
                                    y: .random(in: 0.04...0.62, using: &generator) * size.height)
                let radius = size.width * .random(in: 0.004...0.009, using: &generator)
                let alpha = Double.random(in: 0.35...0.9, using: &generator)
                let shape = index % 5 == 0
                    ? Starfield.sparkle(center: point, radius: radius * 3)
                    : Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(shape, with: .color(.white.opacity(alpha)))
            }
        }

        let moonRadius = size.width * 0.095
        let moon = CGPoint(x: size.width * .random(in: 0.68...0.8, using: &generator), y: size.height * .random(in: 0.13...0.19, using: &generator))
        context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius * 3.2, y: moon.y - moonRadius * 3.2, width: moonRadius * 6.4, height: moonRadius * 6.4)),
                     with: .radialGradient(Gradient(colors: [palette.moon.opacity(0.4), palette.moon.opacity(0)]), center: moon, startRadius: 0, endRadius: moonRadius * 3.2))
        let disc = Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2))
        if palette.seed % 3 == 0 {
            context.fill(disc, with: .color(palette.moon))
        } else {
            let shadow = Path(ellipseIn: CGRect(x: moon.x - moonRadius * 0.45, y: moon.y - moonRadius * 1.3, width: moonRadius * 2, height: moonRadius * 2))
            context.fill(disc.subtracting(shadow), with: .color(palette.moon))
        }

        let phase = Double.random(in: 0...1, using: &generator)
        context.fill(hill(in: size, baseline: 0.74, amplitude: 0.035, phase: phase), with: .color(palette.hillFar))
        context.fill(hill(in: size, baseline: 0.85, amplitude: 0.03, phase: phase + 0.37), with: .color(palette.hillNear))
    }

    private static func hill(in size: CGSize, baseline: Double, amplitude: Double, phase: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for step in 0...40 {
            let t = Double(step) / 40
            let wave = sin((t * 0.9 + phase) * .pi * 2) + 0.35 * sin((t * 2.3 + phase * 1.7) * .pi * 2)
            path.addLine(to: CGPoint(x: t * size.width, y: size.height * (baseline - wave * amplitude)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// A picture-book silhouette: a gently rounded spine edge and softer page corners.
struct BookShape: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: radius * 0.35, bottomLeadingRadius: radius * 0.35,
                               bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> BookShape { BookShape(radius: radius, inset: inset + amount) }
}

extension View {
    /// Frames a cover like a real picture book with a spine, edge highlight and soft shadow.
    func bookStyle(width: CGFloat, shadow: Bool = true) -> some View {
        let radius = max(3, min(14, width * 0.055))
        return self
            .overlay(alignment: .leading) {
                LinearGradient(stops: [.init(color: .black.opacity(0.24), location: 0), .init(color: .black.opacity(0.06), location: 0.55),
                                       .init(color: .white.opacity(0.18), location: 0.72), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(3, width * 0.055))
            }
            .clipShape(BookShape(radius: radius))
            .overlay(BookShape(radius: radius).strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
            .shadow(color: shadow ? Theme.shadow : .clear, radius: max(2, width * 0.05), y: max(1, width * 0.035))
    }
}
