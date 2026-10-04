# Always Near Stories

An iOS 27 / iPadOS 27 audiobook library built with SwiftUI and Apple frameworks.
Bundle ID: `com.matteozajac.bedtimestories`. Created by **Mateusz Zając**.

At first launch, tap **Continue** to use the default **Always Near Stories / Books** library in iCloud Drive. The app creates it automatically; when iCloud Drive is unavailable, it uses on-device storage and copies those books into iCloud when it becomes available. Existing selected libraries are copied without deleting their originals. Share `.bedtimestory` files with family through Files; sharing a folder does not automatically connect another person’s app library. See [storage and family sharing](docs/ICLOUD_LIBRARY.md). Books contain `book.json` and optional text, covers, chapter illustrations, and audio. Read, listen in the background, keep books offline, and share portable `.bedtimestory` files. Reading/listening progress belongs to each device. These library and manual recording flows work without an app account.

Tap **+ → Create a Book** to write chapter text, add photos, and record narration inside the app. Pause/resume a take, review it, then choose **Use Recording**; M4A, MP3 and WAV imports are also supported. Drafts autosave on the device and can be reopened from **Book Creator**. **Save** writes the book to the default library. Open a book’s actions menu and choose **Edit Book** to change its details, text, pictures, recordings, and chapters. **Discard** restores the version from the start of the editing session; **Close** appears when nothing has changed. See [the creator guide and validation](docs/CREATOR.md).

In **Book Creator → Create from an Idea**, describe a story and choose its language, reader age, and the whole book’s reading time and words per minute. The model chooses the chapter count. Apple Foundation Models writes the complete story in one response on the device by default. All chapters and their combined word count are validated together before an editable draft is saved. Release builds enable the explicitly selected Private Cloud Compute mode using Apple's approved managed entitlement; Debug remains local-only. An incomplete response is retried once; incomplete books are never saved as successful new drafts. Apple Image Playground can create cover and chapter illustrations from prepared story prompts and a shared style. See [AI creation and setup](docs/AI_CREATOR.md) and [the iOS 27 API research](docs/FOUNDATION_MODELS_RESEARCH.md).

Optional parent voice narration is implemented in **Settings → Your Voices** and **Book Creator → Create Narration**. It uses Sign in with Apple, Firebase Auth/App Check, owner-only metadata and audio, encrypted retained reference/consent recordings, and a private Gemini 3.8 worker. Choose a book delivery style or paragraph overrides, preview the opening, then explicitly accept the complete narration into the working draft. Only rendered audio enters the ordinary library or exports. Firebase Apple SDK dependencies are pinned to 12.19.2; Gemini authentication uses backend service accounts, with no Gemini API key in the app. Cloud narration is enabled for the main app’s Internal build in the existing Always Near Stories project; physical voice/device acceptance remains open. See [cloud narration architecture, setup and gates](docs/CLOUD_NARRATION.md).

MZAppFoundation **0.3.1** supplies structured local Pulse logging. With **Settings → Developer → Developer Mode** enabled, shake the device to open the console, or choose **Open Logs**. Local/Debug/Internal builds default to enabled; production defaults to disabled, and an explicit choice persists. Remote analytics and diagnostics remain disabled. Use the **BedtimeStoriesLocal** scheme for simulator development; it excludes the Firebase backend SDKs and keeps cloud narration unavailable. See [diagnostics setup and verification](.mzappfoundation/README.md).

See the [book format](skills/bedtime-book-create/references/book-format.md) and [authoring skill](skills/bedtime-book-create/SKILL.md). The skill's maintained source is in this repository; a copy is installed in `~/.codex/skills/bedtime-book-create` for Codex discovery. To update it, copy this skill directory into that location.

```sh
python3 skills/bedtime-book-create/scripts/book.py create --title 'The Sleepy Fox' --text story.md --output /tmp/SleepyFox --archive /tmp/SleepyFox.bedtimestory
swift test
python3 -m unittest discover -s Tests/Authoring -v
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStoriesLocal -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Open `BedtimeStories.xcodeproj` with Xcode 27. The UI uses a book grid, an adaptive iPad detail pane, a floating Liquid Glass mini player, and a full-screen audio player, without tabs. Its storybook look (warm paper by day, a calm night sky by night, serif story text, rounded app chrome and illustrated placeholder covers) lives in `BedtimeStories/Design`. The root Swift package is a dependency-free host test harness for the same core sources compiled by the app.

For device checks and evidence boundaries, see [validation](docs/VALIDATION.md).

Long-running story, narration, voice, and library operations have a persistent app-owned history in **Settings → Ongoing Operations**. Completion banners and notification links open the original result, and cloud jobs continue independently of their screens. English and Polish each include three built-in storytellers. See [the operation audit and recovery behavior](docs/BACKGROUND_OPERATIONS.md) and [the backend contract](docs/BACKGROUND_OPERATIONS_BACKEND.md).

Story creation also offers **Gemini**, through the same Apple-authenticated Firebase backend, for Polish and English. Accept the processing disclosure before sending an idea; the complete story opens in the existing draft editor. On-device Foundation Models and Private Cloud Compute remain explicit choices. See [creator processing and validation](docs/AI_CREATOR.md).
