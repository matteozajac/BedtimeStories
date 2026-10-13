import Foundation

/// A reserved processing identity lets developer audio be reopened without a saved book.
public enum FreeTextNarrationDraft {
    public static let id = UUID(uuidString: "F0EE7E87-8445-4E76-B417-ED362C768D04")!
    public static let maximumCharacters = 4_000

    public static func isValid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.utf16.count <= maximumCharacters && !text.contains("\0")
    }

    public static func make(text: String, title: String) throws -> BookDraft {
        guard isValid(text) else { throw BookError.invalid("Enter between 1 and 4,000 characters of text.") }
        var draft = BookDraft(id: id)
        draft.title = title
        draft.chapters = [DraftChapter(text: text)]
        return draft
    }
}
