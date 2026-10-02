# Playback artwork crash — 2 October 2026

App Store Connect app `6818278413` (`com.matteozajac.bedtimestories`) returned one crash submission and no screenshot feedback during this investigation. Submission `ADBBvgNbyzGGCbY4RjgdH7g` describes opening the book player or starting listening. Its crash log identifies **1.0 (7)** running as an iOS-compatible app on **Vision Pro, visionOS 27.2**.

The faulting thread is a MediaPlayer background queue. The stack enters `closure #2 in closure #1 in StoryPlayer.load(index:at:autoplay:)`, through the `(CGSize) -> UIImage` artwork request handler, then fails Swift's actor-executor check. The closure inherited `@MainActor` from `StoryPlayer`, although the system invokes it off that actor. The same callback was still present in the build-8 source.

## Fix and regression

The artwork request handler is explicitly `@Sendable`, captures only the decoded immutable image, and can return it synchronously on the system's queue. The six remote-command handlers use the same annotation; their player actions continue to run in explicit `@MainActor` tasks. No library, book, recording, or progress migration is involved.

`LibraryPlaybackTests.coverArtworkCanBeRequestedOffMainActor()` plays a real fixture WAV with a PNG cover, waits for publication to `MPNowPlayingInfoCenter`, then requests two artwork sizes from a detached task. It checks that it is off the main thread, both requests return the cover, and playback progress was saved. Existing playback fixtures lacked cover images and therefore missed this path.

Before the fix, running the playback suite crashed the test host with `EXC_BREAKPOINT / SIGTRAP`. The simulator report contains `_dispatch_assert_queue_fail`, `_swift_task_checkIsolatedSwift`, and the same `StoryPlayer.load` artwork callback as the submitted Vision Pro report. Xcode restarted the test host and ran the remaining three playback tests; its post-crash result collection stalled, so that invocation was terminated after capturing the crash report and log. After the fix, the covered-book regression and all **33 native tests in four suites passed in Release on iPhone and Debug on iPad**, with no failures or skips in either completed result bundle.

## Repeat

```sh
xcodebuild test -project BedtimeStories.xcodeproj -scheme BedtimeStoriesLocal \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -only-testing:BedtimeStoriesLocalTests/LibraryPlaybackTests
```

Omit `-only-testing` for the complete native suite. `ENABLE_TESTABILITY=YES` is an invocation-only override for Release tests, not a distribution build setting.

After the foundation integration, all 39 native tests in six suites also passed
in optimized `Internal` on the iPhone simulator, including this artwork regression.
Simulator runs now use `BedtimeStoriesLocal`, which excludes remote SDKs.

Temporary host evidence:

- `/tmp/bedtime-player-crash.json`: original App Store Connect crash log, kept outside the repository.
- `/tmp/bedtime-player-red-3.log`: pre-fix reproduction and test-host restart.
- `/Users/mateusz/Library/Logs/DiagnosticReports/BedtimeStories-2026-10-02-191915.ips`: matching simulator executor trap.
- `/tmp/BedtimeStories-player-green-release.xcresult`: complete Release pass, including the covered-book regression.
- `/tmp/BedtimeStories-player-green-ipad.xcresult`: complete Debug pass on iPad, including the covered-book regression.

The regression validates the actual artwork callback on an iPhone simulator. Physical Vision Pro playback, system media controls, background audio and AirPlay still require device retesting with a corrected distributed build.
