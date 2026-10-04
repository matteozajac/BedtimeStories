import Foundation

enum OperationDestination: Codable, Equatable, Sendable {
    case book(UUID), draft(UUID), narration(UUID), voices, operations, importReview
}

struct AppOperation: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case voiceEnrollment, narration, storyGeneration, download, importBook, saveBook, shareBook, voicePreview
    }
    enum State: String, Codable, Sendable { case queued, running, ready, failed, cancelled, interrupted }
    let id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var progress: Double?
    var state: State = .queued
    var destination: OperationDestination
    var createdAt = Date()
    var updatedAt = Date()
    var message: String?
    var ownerID: String?
    var remoteID: String?
    var remoteExpiresAt: Date?
    var hiddenFromHistory: Bool?
    var cancellationDisabled: Bool?
    var completionPresentedAt: Date?
    var readingWordsPerMinute: Int?
    var isActive: Bool { state == .queued || state == .running }
    var canCancel: Bool { isActive && cancellationDisabled != true }
    var isTerminal: Bool { !isActive }
    var icon: String {
        switch kind {
        case .voiceEnrollment: "person.wave.2.fill"
        case .narration, .voicePreview: "waveform"
        case .storyGeneration: "sparkles"
        case .download: "arrow.down.circle.fill"
        case .importBook: "square.and.arrow.down"
        case .saveBook: "book.closed.fill"
        case .shareBook: "square.and.arrow.up"
        }
    }
    var deepLink: URL { URL(string: "bedtimestories://operation/\(id)")! }
    static func operationID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "bedtimestories", components.host == "operation",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty, !parts[1].isEmpty,
              parts[1].count <= 128, parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return String(parts[1])
    }
}
