import SwiftUI

struct OperationsView: View {
    @Environment(OperationCenter.self) private var operations

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introduction
                if !operations.activeOperations.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow("In Progress")
                        ForEach(operations.activeOperations) { OperationRowView(operation: $0) }
                    }
                }
                if !operations.completedOperations.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Eyebrow("Recent Operations")
                            Spacer()
                            Button("Clear History") { operations.clearHistory() }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        ForEach(operations.completedOperations) { OperationRowView(operation: $0) }
                        Text("Clearing this list keeps your books, drafts, and voices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background { StoryBackground() }
        .navigationTitle("Ongoing Operations")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ongoing-operations")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: operations.activeOperations.isEmpty ? "moon.zzz.fill" : "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.glow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    if operations.activeOperations.isEmpty {
                        Text("A quiet moment")
                            .storyFont(.title2, weight: .bold)
                        Text("Nothing is running right now. Start your next bedtime story whenever you’re ready.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.moonlight.opacity(0.8))
                    } else {
                        Text("A little magic in progress")
                            .storyFont(.title2, weight: .bold)
                        Text("You can keep exploring. We’ll let you know when your story or voice is ready.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.moonlight.opacity(0.8))
                    }
                }
                .foregroundStyle(Theme.moonlight)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !operations.activeOperations.isEmpty {
                Text("\(operations.activeOperations.count) in progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.moonlight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background { NightCardBackground(seed: 0x0B5E) }
    }
}
