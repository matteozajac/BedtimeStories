# Validation — 30 September 2026

Built with Xcode 27 and the iOS 27 SDK. The Release device build succeeds with signing disabled; this is build evidence, not a signed archive or distribution upload. The built Info.plist confirms bundle `com.matteozajac.bedtimestories`, minimum OS 27.0, iPhone/iPad support, background audio, and the `.bedtimestory` document type.

## Automated checks

| Check | Result |
| --- | --- |
| `swift test` | 8 test functions passed, including 7 unsafe-path cases |
| Python authoring unittest suite | 6 passed |
| Native library/player integration tests on iPhone 18 Pro, iOS 27 | 3 passed |
| Native library/player integration tests on iPad Pro 13-inch M5, iPadOS 27 | 3 passed |
| Maestro iPhone library → player → mini player → reader → Settings | All 24 commands passed |
| Installed authoring skill structure validation | Passed |
| Release generic iOS build, signing disabled | Passed |

Core checks cover optional content, manifest validation, timestamp/recording layouts, unsafe paths, CRC corruption, truncated archives, missing assets, symlinks, malicious archive variants, Python/Swift archive interoperability, text parsing, playback boundaries, and progress serialization. Native integration checks cover scanning past a malformed book, offline pinning, exports/imports/replacement, cached content after the source disappears, cleanup, playback seeking, chapter selection, automatic advancement, sleep-at-chapter-end, speed, and resume without autoplay.

UI exploration also exercised the mandatory folder picker against a local simulator folder, chapter reading navigation, duplicate-book import confirmation/cancellation, and the native share sheet with the exported `.bedtimestory` and Save to Files action. Simulator fixtures contain silent WAV audio to exercise player state; they are not narrated stories. The iPad screenshots below come from that iPad's native simulator capture. Maestro's hierarchy routing returned the iPhone for an iPad request, so no iPad Maestro interaction pass is claimed.

## Screenshots

- [iPhone library and floating player](qa/iphone-library.png)
- [iPad library with book detail](qa/ipad-library.png)
- [iPad full-screen player](qa/ipad-player.png)
- [iPhone native share sheet](qa/iphone-share.png)

## Reproduce

```sh
swift test
python3 -m unittest discover -s Tests/Authoring -v
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

For UI checks, install the Debug app on a disposable iOS 27 simulator, then run `python3 scripts/seed-simulator.py YOUR_SIMULATOR_UUID`. Launch normally and choose **On My iPhone → Bedtime Stories → QA Library**. Alternatively, the Debug-only `--qa-library` launch argument chooses that existing simulator fixture folder. `--qa-book` selects the first sample book and `--qa-player` opens its player for layout capture. Release builds ignore these arguments. Run `maestro --device YOUR_SIMULATOR_UUID test Tests/UI/library-player.yaml` in English. The authoring skill and simulator fixture tooling do not write to your iCloud library.

## Real-device checks still required

1. Choose the same shared iCloud Drive folder on two Apple accounts. Add/edit/remove a book from Files and verify each library refreshes. Check evicted iCloud placeholders, slow download/cancellation, a moved folder, revoked access, and reselection after relaunch.
2. Pin a book, disconnect the network, then relaunch and read/listen. Remove its offline download and verify the source folder remains intact.
3. Play real narration with the screen locked and the app in the background. Exercise Control Center/Lock Screen play, pause, seeking, artwork, sleep timer, interruptions, headset disconnect, and AirPlay.
4. Share a `.bedtimestory` through Files/AirDrop to another device and open it in the app. Check replacement confirmation and a read-only destination folder.
5. Check larger Dynamic Type, VoiceOver, rotation, iPad multitasking, and Reduce Transparency/Motion on hardware.

Reading resumes at the chapter level; it does not save paragraph or scroll offsets. `.bedtimestory` imports use the documented stored ZIP32 profile: arbitrary compressed/encrypted/ZIP64 archives are rejected. iCloud sharing is managed through Files rather than an in-app account or invitation system.
