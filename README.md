# Always Near Stories

An iOS 27 / iPadOS 27 audiobook library built with SwiftUI and Apple frameworks.
Bundle ID: `com.matteozajac.bedtimestories`. Created by **Mateusz Zając**.

Choose an iCloud Drive folder (including one shared with family) at first launch. Add book folders containing `book.json` and optional text, covers, chapter illustrations, and audio. Read, listen in the background, keep books offline, and share portable `.bedtimestory` files. Reading/listening progress belongs to each device. There are no accounts, AI services, analytics, or third-party dependencies.

Tap **+ → Create a Book** to write chapter text, add photos, and record narration inside the app. Pause/resume a take, review it, then choose **Use Recording**; M4A, MP3 and WAV imports are also supported. Drafts autosave on the device and can be reopened from **Book Creator**. **Add to Library** writes the completed book to the chosen library folder in the same portable format. See [the creator guide and validation](docs/CREATOR.md).

See the [book format](skills/bedtime-book-create/references/book-format.md) and [authoring skill](skills/bedtime-book-create/SKILL.md). The skill's maintained source is in this repository; a copy is installed in `~/.codex/skills/bedtime-book-create` for Codex discovery. To update it, copy this skill directory into that location.

```sh
python3 skills/bedtime-book-create/scripts/book.py create --title 'The Sleepy Fox' --text story.md --output /tmp/SleepyFox --archive /tmp/SleepyFox.bedtimestory
swift test
python3 -m unittest discover -s Tests/Authoring -v
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Open `BedtimeStories.xcodeproj` with Xcode 27. The UI uses a book grid, an adaptive iPad detail pane, a floating Liquid Glass mini player, and a full-screen audio player, without tabs. The root Swift package is a dependency-free host test harness for the same core sources compiled by the app.

For device checks and evidence boundaries, see [validation](docs/VALIDATION.md).
