import Testing
@testable import BedtimeCore

struct BookErrorDiagnosticsTests {
    @Test func technicalReasonsRetainMeaningWithoutDynamicBookData() {
        #expect(BookError.unavailable("iCloud has not finished downloading this file. Check your connection and try again.").diagnosticMessage.contains("iCloud has not finished"))
        #expect(BookError.invalid("Missing file: private-family-name.md").diagnosticMessage == "A referenced book asset is missing.")
        #expect(BookError.invalid("Unsupported book version: 91.").diagnosticMessage.contains("unsupported format version"))
        #expect(BookError.invalid("private story text https://private.invalid").diagnosticMessage == "The book or one of its assets failed validation.")
        #expect(BookError.unavailable("/Users/private/parent-recording.wav").diagnosticMessage == "The book, asset, or file provider is unavailable.")
        #expect(BookError.editConflict.diagnosticMessage.contains("working draft is preserved"))
    }
}
