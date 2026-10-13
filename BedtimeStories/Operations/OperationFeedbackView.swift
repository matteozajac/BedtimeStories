import SwiftUI

/// Place on each presentation surface so updates remain visible above sheets.
/// Only the most recently presented surface draws the banner, so it never repeats behind a sheet.
struct OperationFeedbackView: ViewModifier {
    @Environment(OperationCenter.self) private var operations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surface = UUID()

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let operation = operations.banner, operations.feedbackSurfaces.last == surface {
                    OperationBannerView(operation: operation)
                        .frame(maxWidth: 600)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12), value: operations.banner?.id)
            .onAppear { operations.surfaceAppeared(surface) }
            .onDisappear { operations.surfaceDisappeared(surface) }
            .alert("Unable to complete", isPresented: Binding(get: { operations.message != nil }, set: { if !$0 { operations.message = nil } })) { } message: {
                Text(operations.message ?? "")
            }
    }
}

extension View {
    func operationFeedback() -> some View { modifier(OperationFeedbackView()) }
}
