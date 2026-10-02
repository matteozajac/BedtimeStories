import XCTest
@testable import BedtimeCore

final class NarrationSnapshotTests: XCTestCase {
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
