import Foundation

public struct LibraryBook: Identifiable, Codable, Hashable, Sendable {
    public var manifest: BookManifest
    public var folder: URL
    public var id: UUID { manifest.id }
    public init(manifest: BookManifest, folder: URL) { self.manifest = manifest; self.folder = folder }
}
