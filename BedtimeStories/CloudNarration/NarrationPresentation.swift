import SwiftUI

extension NarrationStyle {
    var symbolName: String {
        switch self {
        case .natural: "text.bubble.fill"
        case .gentle: "leaf.fill"
        case .curious: "sparkle.magnifyingglass"
        case .excited: "sun.max.fill"
        case .reassuring: "heart.fill"
        case .whispered: "moon.zzz.fill"
        }
    }
}

/// A voice's processing status as a colored pill.
struct VoiceStatusPill: View {
    let status: String

    var body: some View {
        switch status {
        case "ready": StatusPill(title: String(localized: "Ready"), systemImage: "checkmark.seal.fill", color: Theme.ready)
        case "processing": StatusPill(title: String(localized: "Preparing"), systemImage: "hourglass", color: Theme.glow)
        case "awaitingApproval": StatusPill(title: String(localized: "Review Your Voice"), systemImage: "ear.fill", color: Theme.glow)
        case "deleting": StatusPill(title: String(localized: "Deleting"), systemImage: "trash.fill", color: .secondary)
        case "failed": StatusPill(title: String(localized: "Try Again"), systemImage: "exclamationmark.triangle.fill", color: Theme.recording)
        default: StatusPill(title: String(localized: "Unavailable"), systemImage: "minus.circle.fill", color: .secondary)
        }
    }
}

/// A round night sky with a waveform, standing in for a saved voice.
struct VoiceAvatar: View {
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color(hex: 0xF5C77E))
            .frame(width: size, height: size)
            .background(NightCardBackground(cornerRadius: size / 2, seed: 0x5011))
            .overlay(Circle().strokeBorder(Theme.moonlight.opacity(0.18)))
            .accessibilityHidden(true)
    }
}

/// A capsule showing a narration style; filled when it is the chosen one.
struct NarrationStyleChip: View {
    let title: String
    let style: NarrationStyle
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.symbolName).accessibilityHidden(true)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(selected ? Theme.onAccent : Theme.accent)
        .padding(.horizontal, 14).frame(minHeight: 38)
        .background(selected ? Theme.accent : Theme.accentSoft, in: .capsule)
    }
}

/// Lays out children in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty && needed > width {
                rows.append(row); row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
