import SwiftUI

/// Place on each presentation surface so updates remain visible above sheets.
struct OperationFeedbackView: ViewModifier {
    @Environment(OperationCenter.self) private var operations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let operation = operations.banner {
                    OperationBannerView(operation: operation)
                        .frame(maxWidth: 600)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12), value: operations.banner?.id)
            .alert("Unable to complete", isPresented: Binding(get: { operations.message != nil }, set: { if !$0 { operations.message = nil } })) { } message: {
                Text(operations.message ?? "")
            }
    }
}

extension View {
    func operationFeedback() -> some View { modifier(OperationFeedbackView()) }
}
