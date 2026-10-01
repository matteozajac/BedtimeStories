import Foundation

public enum SafeBookPath {
    public static func validate(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 }),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw BookError.invalid("Unsafe file path: \(path).")
        }
    }

    public static func resolve(_ path: String, inside folder: URL) throws -> URL {
        try validate(path)
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        var current = root
        for part in path.split(separator: "/") {
            current.appendPathComponent(String(part))
            let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { throw BookError.invalid("Symbolic links are not allowed in books.") }
        }
        let resolved = current.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else { throw BookError.invalid("File leaves the book folder.") }
        return current
    }
}
