import SwiftUI

struct OperationBannerView: View {
    @Environment(OperationCenter.self) private var operations
    let operation: AppOperation

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button { operations.openOperation(id: operation.id) } label: {
                HStack(alignment: .top, spacing: 14) {
                    IconTile(systemName: operation.state == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                             color: operation.state == .ready ? Theme.ready : Theme.recording, size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(operation.state == .ready ? "Ready for you" : "Needs your attention")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(operation.state == .ready ? Theme.ready : Theme.recording)
                        Text(operation.title)
                            .storyFont(.headline, weight: .semibold)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        if !operation.subtitle.isEmpty {
                            Text(operation.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Label("Tap to open", systemImage: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .labelStyle(CompactLabelStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 16)
                .padding(.leading, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("operation-completion-" + operation.id)
            Button("Dismiss update", systemImage: "xmark") { operations.dismissBanner() }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .padding(.top, 4)
        }
        .background(Theme.surface, in: .rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.surfaceStroke))
        .shadow(color: Theme.shadow, radius: 16, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
