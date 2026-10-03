import Foundation

/// Cancels the client's wait without allowing late cloud responses to mutate app state.
@MainActor
enum CloudStoryResponse {
    static func wait(start: (@escaping @Sendable (Result<Data, any Error>) -> Void) -> Void) async throws -> Data {
        try Task.checkCancellation()
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            start { result in
                switch result {
                case .success(let data): continuation.yield(data); continuation.finish()
                case .failure(let error): continuation.finish(throwing: error)
                }
            }
        }
        for try await data in stream {
            try Task.checkCancellation()
            return data
        }
        throw CancellationError()
    }
}
