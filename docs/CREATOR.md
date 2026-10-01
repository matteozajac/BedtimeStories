# Book Creator

Open **+** in Library, or **Create a Book** on the welcome screen. Choose **Create a Book** in the draft browser, enter a title and optional author/description, and add a cover photo.

Open a chapter to write its text, choose a picture, and record narration. The recorder shows the chapter text while you read. It supports pause/resume, finishing, preview, rerecording and **Use Recording**. Canceling a take leaves existing chapter narration intact. You can also import M4A, MP3 or WAV audio and preview it from the chapter editor.

Use **Edit** to reorder or remove chapters. Text, photos and accepted recordings autosave to a local draft; **Save Draft** saves immediately and returns to the draft browser. Reopen the draft to continue. Drafts belong to this device and are not placed in the shared library until you choose **Add to Library**. A book can begin with just its title.

If no library folder has been selected, choose one from the editor first. Adding the book uses the existing coordinated import path and a new stable book ID. A failed write preserves the draft. The completed book appears in Library, works with reading and playback, and can be downloaded or exported as `.bedtimestory`. This creator makes new books; existing published books remain editable through their folders in Files.

## Recording behavior

Microphone permission is requested when starting a recording. If permission is denied, the recorder offers Settings; writing and audio import remain available. Recording pauses when the app leaves the foreground, when the audio session is interrupted, or when an input route disconnects. Resume requires an explicit tap. A replacement take is copied and validated before it is attached to the draft. Recordings stay in the app/library folder and are not sent to an audio service.

## Validation — 1 October 2026

- 8 Swift core tests and 6 Python authoring tests passed.
- 7 native tests passed on each iPhone and iPad simulator: the existing 3 library/player tests plus 4 creator tests.
- Creator tests verify reopening and stale autosave protection, stable chapter order, text/audio publication and sharing, invalid audio replacement, failed destination writes, blank-title rejection and unsafe paths.
- iPhone UI exploration verified creating a draft, typing a title, recovery after termination/relaunch, opening a chapter, entering text, starting/pausing/finishing a simulator recording, accepting the 18-second take and adding the book to Library.
- iPad UI exploration verified the Polish draft browser, editor, chapter navigation, saved-draft status, microphone permission request, resume/finish and confirmed discard of a take. English and Polish microphone purpose strings are present in the signed IPA.
- Release archive/export and signature verification succeeded for 1.0 (3), with Internal-only export and unchanged source fingerprints.

The simulator produced a valid recorded file; this does not establish intelligibility or microphone quality on hardware. Before relying on recording, test real speech, wired/Bluetooth input, permission denial and recovery, calls, screen locking/backgrounding, pause/resume, cancellation, rerecording and playback on an iPhone/iPad. Photos from the real photo library and actual shared-iCloud write/recovery behavior also need device testing.
