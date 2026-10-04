import ActivityKit
import Foundation

struct OperationActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var operationID: String
        var title: String
        var subtitle: String
        var progress: Double
        var state: String
    }
    var operationID: String
}
