import SwiftUI

/// A glowing crescent moon with a few sparkles, used for welcome and quiet moments.
struct MoonIllustration: View {
    var size: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.moonlight.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: size))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(breathing ? 1.08 : 0.94)
            CrescentShape()
                .fill(LinearGradient(colors: [Color(hex: 0xFFF6E2), Color(hex: 0xF5C77E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: Color(hex: 0xF5C77E).opacity(0.55), radius: size * 0.22)
            sparkle(size * 0.2, x: size * 0.62, y: -size * 0.48)
            sparkle(size * 0.12, x: size * 0.82, y: -size * 0.08)
            sparkle(size * 0.09, x: -size * 0.7, y: -size * 0.42)
        }
        .frame(width: size * 2, height: size * 1.6)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    private func sparkle(_ side: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: side, weight: .medium))
            .foregroundStyle(Color(hex: 0xF5C77E))
            .opacity(breathing ? 1 : 0.55)
            .offset(x: x, y: y)
    }
}

struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect).subtracting(Path(ellipseIn: rect.offsetBy(dx: rect.width * 0.36, dy: -rect.height * 0.2)))
    }
}
