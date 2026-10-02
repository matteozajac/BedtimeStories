import Foundation

public struct BookManifest: Codable, Identifiable, Hashable, Sendable {
    public var formatVersion: Int
    public var id: UUID
    public var title: String
    public var author: String?
    public var description: String?
    public var cover: String?
    public var audio: String?
    public var chapters: [BookChapter]?
    public var readingWordsPerMinute: Int?
    public var illustrationGuide: String?

    public init(id: UUID = UUID(), title: String, author: String? = nil, description: String? = nil, cover: String? = nil, audio: String? = nil, chapters: [BookChapter] = []) {
        formatVersion = 1; self.id = id; self.title = title; self.author = author
        self.description = description; self.cover = cover; self.audio = audio; self.chapters = chapters
    }

    public var orderedChapters: [BookChapter] { chapters ?? [] }
    public var hasAudio: Bool { audio != nil || orderedChapters.contains { $0.audio != nil } }
    public var hasReading: Bool { orderedChapters.contains { $0.text != nil || $0.image != nil } }
    public var assetPaths: [String] {
        ([cover, audio] + orderedChapters.flatMap { [$0.text, $0.image, $0.audio] }).compactMap { $0 }
    }

    public func validate() throws {
        guard formatVersion == 1 else { throw BookError.invalid("Unsupported book version: \(formatVersion).") }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookError.invalid("A book needs a title.") }
        guard orderedChapters.count <= 9_999 else { throw BookError.invalid("Too many chapters.") }
        guard Set(orderedChapters.map(\.id)).count == orderedChapters.count else { throw BookError.invalid("Chapter identities must be unique.") }
        guard audio == nil || !orderedChapters.contains(where: { $0.audio != nil }) else {
            throw BookError.invalid("Use a full-book recording or chapter recordings, not both.")
        }
        try validateExtension(cover, allowed: ["jpg", "jpeg", "png", "heic"])
        try validateExtension(audio, allowed: ["m4a", "mp3", "wav"])
        var previous: Double = -1
        var timestampCount = 0
        for chapter in orderedChapters {
            try validateExtension(chapter.text, allowed: ["md", "txt"])
            try validateExtension(chapter.image, allowed: ["jpg", "jpeg", "png", "heic"])
            try validateExtension(chapter.audio, allowed: ["m4a", "mp3", "wav"])
            if let start = chapter.startTime {
                guard audio != nil, start.isFinite, start >= 0, start > previous else {
                    throw BookError.invalid("Chapter timestamps need a full-book recording and must increase from zero or later.")
                }
                previous = start; timestampCount += 1
            }
        }
        guard timestampCount == 0 || timestampCount == orderedChapters.count else {
            throw BookError.invalid("Provide timestamps for every chapter or omit them all.")
        }
        for path in assetPaths { try SafeBookPath.validate(path) }
        let uniquePaths = Set(assetPaths)
        let canonicalPaths = Set(uniquePaths.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        guard uniquePaths.count == canonicalPaths.count else { throw BookError.invalid("Asset paths collide on Apple filesystems.") }
    }

    private func validateExtension(_ path: String?, allowed: Set<String>) throws {
        if let path, !allowed.contains((path as NSString).pathExtension.lowercased()) {
            throw BookError.invalid("Unsupported asset type: \(path).")
        }
    }

    public static func load(from folder: URL, requireAssets: Bool = false) throws -> BookManifest {
        let url = try SafeBookPath.resolve("book.json", inside: folder)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 2_000_000 else { throw BookError.invalid("Book manifest is too large.") }
        let book = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try book.validate()
        if requireAssets {
            for path in book.assetPaths {
                let asset = try SafeBookPath.resolve(path, inside: folder)
                guard try asset.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw BookError.invalid("Missing file: \(path).")
                }
            }
        }
        return book
    }
}
