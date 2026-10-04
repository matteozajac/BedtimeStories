import SwiftUI

/// A quiet way back to the task list while the reader explores the app.
struct OperationStatusView: View {
    @Environment(OperationCenter.self) private var operations

    var body: some View {
        Button { operations.showingOperations = true } label: {
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(operations.activeOperations.count) in progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("You can keep exploring")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ongoing-operations-status")
    }
}
