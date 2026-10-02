import SwiftUI

/// A calm evening palette chosen from a book's identity, so a book keeps
/// the same colors on every device and in every view.
struct StoryPalette {
    let skyTop: Color
    let skyBottom: Color
    let hillFar: Color
    let hillNear: Color
    let moon: Color
    let seed: UInt64

    init(for id: UUID) {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let seed = bytes.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let colors = Self.palettes[Int(seed % UInt64(Self.palettes.count))]
        skyTop = Color(hex: colors[0]); skyBottom = Color(hex: colors[1])
        hillFar = Color(hex: colors[2]); hillNear = Color(hex: colors[3]); moon = Color(hex: colors[4])
        self.seed = seed
    }

    private static let palettes: [[UInt32]] = [
        [0x7C6DB8, 0x2F2A5E, 0x4B4083, 0x2A2450, 0xFFE6B0], // Lavender dusk
        [0x5088AA, 0x1C3150, 0x2E5878, 0x183049, 0xFFF1C9], // Ocean night
        [0x6F9C7C, 0x22403A, 0x416D58, 0x1F3A31, 0xFFE9B8], // Quiet forest
        [0xC88C9D, 0x4E2C4D, 0x8C5672, 0x4A2843, 0xFFEBC4], // Rose evening
        [0xDDA56B, 0x6A3A40, 0xA6664F, 0x5C3036, 0xFFF3D6], // Honey sunset
        [0x62A4A1, 0x1F3F4F, 0x38717A, 0x1C3A45, 0xFFF0C2], // Teal lagoon
        [0x8F84C9, 0x3A3570, 0x5E558F, 0x2F2A58, 0xFFE2A8]  // Periwinkle
    ]
}

/// A tiny deterministic generator so illustrations look the same on every render.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
