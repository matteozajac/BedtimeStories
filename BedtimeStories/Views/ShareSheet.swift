import SwiftUI
import UIKit
import MZAppFoundation

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        AppLog.debug("Book system share sheet presented", category: "sharing")
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, returnedItems, error in
            // UIKit callbacks can arrive outside our executor. Capture the original
            // error and reporting frames before delivering to the main actor logger.
            let snapshot = error.map { ErrorSnapshot($0) }
            let cancelled = error.map { failure in
                let ns = failure as NSError
                return ErrorSnapshot.isCancellation(failure) || (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError)
            } ?? false
            let activityType = activity?.rawValue ?? "none"
            let returnedItemCount = returnedItems?.count ?? 0
            Task { @MainActor in
                let fields: [String: TelemetryValue] = [
                    "activity_type": .string(activityType), "completed": .bool(completed),
                    "returned_item_count": .integer(returnedItemCount)
                ]
                if cancelled {
                    AppLog.trace("Book sharing cancelled", category: "sharing", metadata: fields)
                } else if let snapshot {
                    AppLog.logger.log(LogEntry("Book sharing failed", level: .error, category: "sharing", metadata: fields, error: snapshot))
                } else {
                    AppLog.debug(completed ? "Book sharing completed" : "Book sharing dismissed", category: "sharing", metadata: fields)
                }
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
