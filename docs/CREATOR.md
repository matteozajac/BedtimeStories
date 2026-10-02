# Book Creator

Open **+ → Create a Book** after accepting the automatic library. Enter a title, author and description, and add a cover. **Create from an Idea** instead asks for a description, language, reader age, total reading time, and words per minute. The model chooses the chapter count and writes the entire story together. Only a complete validated book becomes a draft. See [AI creation and PCC](AI_CREATOR.md).

Open any chapter to edit or append its text, add/change/remove a picture, and record or import narration. **Chapter Options** moves a chapter earlier/later or removes it; **Add Chapter** appends one. **Reading Time** shows the combined prose count and approximate whole-book time at the selected pace. Cover and chapter **Generate Picture** buttons open Apple Image Playground with prepared story context and a consistent illustration style; acceptance changes only the working copy.

**Save** publishes a new book or updates the existing library book and closes the editor. The leading button is **Discard** when this session has changes, with confirmation, or **Close** when it does not. Discard restores the opened draft or removes a new empty draft/edit checkout; it never changes the published library book. Local autosave keeps recovery copies if the app is interrupted. These unpublished copies appear in Book Creator on this device. A failed library save preserves the working copy.

Choose **Edit Book** in an existing book’s actions menu. The app downloads and copies every referenced asset, preserves book/chapter identities and existing media, and records a SHA-256 fingerprint. **Save** coordinates a folder replacement and checks that fingerprint again. A changed, deleted, conflicting, or different-account source blocks replacement and offers **Save as a New Book** or **Keep Editing**. The original book and the local edits remain safe. Saving replaces a pinned offline copy with the complete edited book before completing the transaction, and refreshes library detail. The offline test removes the source folder and reads every updated cached asset, including new text and audio. Real iCloud conflict delivery and synchronization still need checks on two devices; an edit that has not arrived locally cannot be detected yet.

Existing full-book narration and chapter timestamps are preserved. **Record a New Take**, **Import Audio**, and **Remove Narration** work on the full recording. Adding/removing/reordering chapters clears old chapter timestamps, while retaining the recording. Remove full-book narration before attaching individual chapter recordings; the portable format supports one audio layout at a time. No automatic alignment of edited text with narration is implied.

## Recording behavior

Microphone permission is requested when starting a recording. If permission is denied, the recorder offers Settings; writing and audio import remain available. Recording pauses when the app leaves the foreground, when the audio session is interrupted, or when an input route disconnects. Resume requires an explicit tap. A replacement take is copied and validated before it is attached to the draft. Manual book recordings stay in the app/library folder. Optional voice enrollment separately asks to upload reference/consent samples for Google voice creation and retain them until deletion.

## Optional generated narration — 2 October 2026

The implemented cloud feature is currently disabled while dedicated project provisioning and live device/provider checks remain pending. Once enabled, **Settings → Your Voices** enrolls an adult's own voice with separate retention acceptance, reference/consent takes and a listening/approval step. **Create Narration** in the editor selects that voice, book delivery style and paragraph overrides. Preview the opening, request the complete narration, then choose **Use Narration** to replace audio in the working draft. **Save** publishes the rendered audio through the existing library/portable format. A preview, changed text/settings, another account or an incomplete result cannot attach as a complete book. See [cloud narration](CLOUD_NARRATION.md) and its [validation receipt](CLOUD_NARRATION_VALIDATION.md).

## Validation — 1 October 2026

- 8 Swift core tests and 6 Python authoring tests passed.
- 7 native tests passed on each iPhone and iPad simulator: the existing 3 library/player tests plus 4 creator tests.
- Creator tests verify reopening and stale autosave protection, stable chapter order, text/audio publication and sharing, invalid audio replacement, failed destination writes, blank-title rejection and unsafe paths.
- iPhone UI exploration verified creating a draft, typing a title, recovery after termination/relaunch, opening a chapter, entering text, starting/pausing/finishing a simulator recording, accepting the 18-second take and adding the book to Library.
- iPad UI exploration verified the Polish draft browser, editor, chapter navigation, saved-draft status, microphone permission request, resume/finish and confirmed discard of a take. English and Polish microphone purpose strings are present in the signed IPA.
- Release archive/export and signature verification succeeded for 1.0 (3), with Internal-only export and unchanged source fingerprints.

The simulator produced a valid recorded file; this does not establish intelligibility or microphone quality on hardware. Before relying on recording, test real speech, wired/Bluetooth input, permission denial and recovery, calls, screen locking/backgrounding, pause/resume, cancellation, rerecording and playback on an iPhone/iPad. Photos from the real photo library and actual shared-iCloud write/recovery behavior also need device testing.
