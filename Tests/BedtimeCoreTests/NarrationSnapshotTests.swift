import XCTest
@testable import BedtimeCore

final class NarrationSnapshotTests: XCTestCase {
    func testFreeTextIsNotTruncatedOrInterpretedAsMarkdown() throws {
        let text = "# Read this literally\n\n- Keep this prefix.\n" + String(repeating: "Goodnight. ", count: 100)
        let draft = try FreeTextNarrationDraft.make(text: text, title: "Free Text Narration")
        let snapshot = NarrationSnapshot(draft: draft, styles: [:], defaultStyle: .natural, plainText: true)
        XCTAssertEqual(draft.id, FreeTextNarrationDraft.id)
        XCTAssertEqual(snapshot.chapters.count, 1)
        XCTAssertEqual(snapshot.chapters[0].paragraphs.map(\.text), [text])
        XCTAssertEqual(snapshot.chapters[0].paragraphs.map(\.style), [.natural])
        XCTAssertNil(draft.source)
        XCTAssertTrue(draft.mediaPaths.isEmpty)
    }

    func testFreeTextLimitsMatchBackendUTF16Counting() throws {
        XCTAssertFalse(FreeTextNarrationDraft.isValid(" \n\t"))
        XCTAssertFalse(FreeTextNarrationDraft.isValid("Hello\0world"))
        XCTAssertTrue(FreeTextNarrationDraft.isValid(String(repeating: "a", count: 4_000)))
        XCTAssertFalse(FreeTextNarrationDraft.isValid(String(repeating: "a", count: 4_001)))
        XCTAssertTrue(FreeTextNarrationDraft.isValid(String(repeating: "🌙", count: 2_000)))
        XCTAssertFalse(FreeTextNarrationDraft.isValid(String(repeating: "🌙", count: 2_001)))
        XCTAssertThrowsError(try FreeTextNarrationDraft.make(text: "", title: ""))
    }

    func testSnapshotKeepsSpokenTextSeparateFromEmotion() throws {
        var draft = BookDraft()
        let chapter = DraftChapter(title: "Night", text: "# Night\n\nThe fox was curious.\n\nThen he fell asleep.")
        draft.chapters = [chapter]
        let snapshot = NarrationSnapshot(draft: draft, styles: [chapter.id: [.curious]], defaultStyle: .gentle)
        XCTAssertEqual(snapshot.chapters[0].paragraphs.map(\.text), ["The fox was curious.", "Then he fell asleep."])
        XCTAssertEqual(snapshot.chapters[0].paragraphs.map(\.style), [.curious, .gentle])
        XCTAssertEqual(snapshot.chapters[0].sourceText, chapter.text)
        XCTAssertEqual(try snapshot.hash.count, 64)
    }

    func testHashChangesForEditsOrderingOrDeliveryAndIgnoresLocalMedia() throws {
        var draft = BookDraft()
        draft.chapters = [DraftChapter(title: "One", text: "A fox."), DraftChapter(title: "Two", text: "A bear.")]
        let baseline = try NarrationSnapshot(draft: draft, styles: [:], defaultStyle: .gentle).hash
        var changed = draft
        changed.chapters[0].text += " Goodnight."
        XCTAssertNotEqual(baseline, try NarrationSnapshot(draft: changed, styles: [:], defaultStyle: .gentle).hash)
        changed = draft; changed.chapters.reverse()
        XCTAssertNotEqual(baseline, try NarrationSnapshot(draft: changed, styles: [:], defaultStyle: .gentle).hash)
        XCTAssertNotEqual(baseline, try NarrationSnapshot(draft: draft, styles: [:], defaultStyle: .excited).hash)
        changed = draft; changed.cover = "cover.jpg"; changed.chapters[0].audio = "manual.m4a"
        XCTAssertEqual(baseline, try NarrationSnapshot(draft: changed, styles: [:], defaultStyle: .gentle).hash)
    }

    func testNarrationSnapshotDoesNotContainVoiceCredentials() throws {
        var draft = BookDraft(); draft.chapters = [DraftChapter(text: "Goodnight.")]
        let data = try JSONEncoder().encode(NarrationSnapshot(draft: draft, styles: [:], defaultStyle: .natural))
        let json = String(decoding: data, as: UTF8.self)
        for forbidden in ["voicekey_", "providerVoice", "token", "consent", "referenceAudio"] {
            XCTAssertFalse(json.contains(forbidden))
        }
    }
}
