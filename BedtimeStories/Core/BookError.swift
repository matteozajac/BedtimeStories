import Foundation
#if canImport(MZAppFoundation)
import MZAppFoundation
#endif

public enum BookError: Error, LocalizedError, Sendable {
    case invalid(String)
    case unavailable(String)
    case duplicate
    case editConflict

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason), .unavailable(let reason): reason
        case .duplicate: "A book with this identity already exists."
        case .editConflict: String(localized: "This book changed after you opened it. Your edits are safe on this device. Save them as a new book, or close and reopen the latest library version.")
        }
    }

    /// Only audited app-authored reasons may enter diagnostics. Book filenames,
    /// arbitrary imported content and dynamically constructed explanations stay private.
    public var diagnosticMessage: String {
        switch self {
        case .duplicate: return "A book with this identity already exists."
        case .editConflict: return "The library book changed after the editor opened it. The working draft is preserved; reopen the latest version or save a new book."
        case .invalid(let reason), .unavailable(let reason):
            if Self.diagnosticReasons.contains(reason) { return reason }
            for (prefix, message) in [
                ("Missing file: ", "A referenced book asset is missing."),
                ("Unsafe file path: ", "A book asset path failed the path safety check."),
                ("Unsupported asset type: ", "A book asset uses an unsupported file type."),
                ("Duplicate archive path: ", "The archive contains duplicate asset paths."),
                ("A file failed its checksum: ", "An archived asset failed checksum verification."),
                ("Unsupported book version: ", "The book manifest uses an unsupported format version.")
            ] where reason.hasPrefix(prefix) { return message }
            if case .invalid = self { return "The book or one of its assets failed validation." }
            return "The book, asset, or file provider is unavailable."
        }
    }

    private static let diagnosticReasons: Set<String> = [
        "A book needs a title.",
        "Archive exceeds import limits.",
        "Archive filenames must be UTF-8.",
        "Archive is empty or too large.",
        "Archive links and special files are not allowed.",
        "Archive needs book.json at its root.",
        "Asset paths collide on Apple filesystems.",
        "Audio is unavailable.",
        "Book exceeds export limits.",
        "Book manifest is too large.",
        "Cannot create imported file.",
        "Cannot create share file.",
        "Chapter identities must be unique.",
        "Chapter text is too large to display.",
        "Chapter timestamps exceed the recording duration.",
        "Chapter timestamps need a full-book recording and must increase from zero or later.",
        "Choose a photo that can be opened on this device.",
        "Choose an M4A, MP3, or WAV recording.",
        "Destination folder is already occupied.",
        "Duplicate book identity.",
        "File leaves the book folder.",
        "Filename or archive is too large.",
        "Image is too large to display.",
        "Import staging folder already exists.",
        "Invalid ZIP directory.",
        "Invalid ZIP metadata.",
        "Invalid directory entry.",
        "Invalid stored file size.",
        "Library migration could not be saved. The originals are safe.",
        "Multiple books share this identity. Resolve the duplicates in Files first.",
        "Only uncompressed, unencrypted Bedtime Story v1 archives are supported.",
        "Overlapping ZIP entries.",
        "Provide timestamps for every chapter or omit them all.",
        "Record the complete consent statement in 2–30 seconds.",
        "Record 10–30 seconds of clear speech in a quiet room.",
        "Some previous books are not ready to copy. The originals are safe. Try again after their downloads finish in Files.",
        "Symbolic links are not allowed in books.",
        "The book could not be opened for saving.",
        "The draft identity has changed.",
        "The file provider did not grant access.",
        "The folder is not available for importing.",
        "The microphone is unavailable.",
        "The preview is unavailable.",
        "The recording is not available. Download it in Files and try again.",
        "The recording is too long. Record a shorter take.",
        "This recording cannot be played.",
        "This recording could not be prepared. Record another take.",
        "This recording has no playable audio.",
        "This recording is too large. Choose a file under 512 MB.",
        "Too many chapters.",
        "Too many files.",
        "Truncated archive or file.",
        "Unsupported or incomplete ZIP archive.",
        "Use a full-book recording or chapter recordings, not both.",
        "Your library is still opening. Try again in a moment.",
        "Your previous library is unavailable. Its books have not been removed.",
        "ZIP filenames disagree.",
        "ZIP headers disagree.",
        "ZIP64 is not supported in v1.",
        "iCloud has not finished downloading this file. Check your connection and try again.",
    ]
}

#if canImport(MZAppFoundation)
extension BookError: LoggableError {
    public var logMessage: String { diagnosticMessage }
}
#endif
