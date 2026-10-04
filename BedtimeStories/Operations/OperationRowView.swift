import SwiftUI

/// One durable task, with real progress when its provider can report it.
struct OperationRowView: View {
    @Environment(OperationCenter.self) private var operations
    let operation: AppOperation
    @State private var confirmingCancellation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(systemName: operation.icon, color: statusColor, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(operation.title)
                        .storyFont(.headline, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !operation.subtitle.isEmpty {
                        Text(operation.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = operation.message, !message.isEmpty,
               operation.state == .failed || operation.state == .interrupted {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if operation.isActive, let progress = operation.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(Theme.accent)
                    .accessibilityLabel(operation.title)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    status
                    Spacer(minLength: 8)
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    status
                    HStack { actions }
                }
            }
            HStack(spacing: 4) {
                Text(operation.isActive ? "Started" : "Updated")
                Text(operation.isActive ? operation.createdAt : operation.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .storyCard(padding: 18, cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("operation-" + operation.id)
    }

    private var status: some View {
        Label(statusTitle, systemImage: statusIcon)
            .labelStyle(CompactLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.12), in: .capsule)
    }

    @ViewBuilder private var actions: some View {
        if operation.destination != .operations {
            Button(openTitle) { operations.openOperation(id: operation.id) }
                .buttonStyle(.storySoft)
                .controlSize(.small)
                .accessibilityIdentifier("open-operation-" + operation.id)
        }
        if operation.canCancel {
            Button("Cancel", role: .destructive) { confirmingCancellation = true }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .confirmationDialog("Cancel this operation?", isPresented: $confirmingCancellation, titleVisibility: .visible) {
                    Button("Cancel Operation", role: .destructive) { operations.cancel(id: operation.id) }
                    Button("Keep Working", role: .cancel) { }
                } message: {
                    Text("The work in progress will stop. Books and recordings already saved stay in your library.")
                }
                .accessibilityIdentifier("cancel-operation-" + operation.id)
        }
    }

    private var openTitle: LocalizedStringKey {
        switch operation.destination {
        case .book: "Open Book"
        case .draft: "Open Draft"
        case .narration: "Review Narration"
        case .voices: "Open Voices"
        case .importReview: "Review Import"
        case .operations: "View Details"
        }
    }

    private var statusTitle: String {
        switch operation.state {
        case .queued: String(localized: "Waiting")
        case .running:
            if let progress = operation.progress {
                min(max(progress, 0), 1).formatted(.percent.precision(.fractionLength(0)))
            } else {
                String(localized: "In progress")
            }
        case .ready: String(localized: "Ready")
        case .failed: String(localized: "Needs attention")
        case .cancelled: String(localized: "Cancelled")
        case .interrupted: String(localized: "Interrupted")
        }
    }

    private var statusIcon: String {
        switch operation.state {
        case .queued: "clock"
        case .running: "sparkles"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .interrupted: "pause.circle"
        }
    }

    private var statusColor: Color {
        switch operation.state {
        case .ready: Theme.ready
        case .failed: Theme.recording
        case .cancelled, .interrupted: .secondary
        case .queued, .running: Theme.accent
        }
    }
}
