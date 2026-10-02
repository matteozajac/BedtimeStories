# App diagnostics

BedtimeStories uses MZAppFoundation **0.3.1**, resolved to
`b538cb94bd853b3b88978ab713df0ff15121ed64`, with Firebase **12.19.2** and Pulse **5.2.1**.
The shared 0.3.1 tag is published in the MZAppFoundation repository.

## Opening the console

- Enable **Settings → Developer → Developer Mode**, then shake the device.
- **Settings → Developer → Open Logs** provides a navigation fallback.
- `bedtimestories://developer/enable` and `bedtimestories://developer/disable`
  control the same persistent preference. Disabling also closes the console.
- Local/Debug/Internal builds default to enabled; production defaults to disabled.
  A saved choice wins over the build default.

Developer controls have English and Polish app translations. The console uses
MZAppFoundation's scoped UIKit shake responder, without app-wide swizzling.

## Logging and delivery

`MZBootstrap.services` owns the logger. App startup installs that sink in `AppLog`;
library, playback, draft editing, narration recording, story generation, and the
device cloud adapter accept an injectable `AppLogging` interface. Tests use
`RecordingLogger`.

Operation boundaries log static technical messages and safe phases, counts,
indexes, and booleans. Actual caught errors retain type, domain, signed code,
nested causes, caller location, and a reporting stack. Error descriptions, story
text, titles, prompts, account identifiers, recordings, and paths are excluded
from diagnostics. Expected generation and library cancellation produces no error
entry. Reporting stacks identify the logging call, rather than the original throw.

Pulse stores logs locally. Remote analytics and diagnostics are disabled in
`config.json`; the product-event schema and purchase catalog are empty. No new
provider resources were provisioned. Existing Firebase Auth/App Check/Firestore/
Functions/Storage ownership remains in the app's cloud narration adapter.

## Build targets and repeatable setup

| Scheme | Purpose |
| --- | --- |
| `BedtimeStoriesLocal` | Simulator app and app tests. Links the local Pulse composition; excludes the two Firebase adapter files and all remote SDKs. Cloud narration uses an unavailable adapter. |
| `BedtimeStories` | Device app. Retains the existing backend SDKs and adds the live foundation composition. `Internal` enables developer mode by default. |

Use the canonical setup script, then the app overlay, in this order:

```sh
python3 /path/to/MZAppFoundation/scripts/setup.py apply --app-root .
ruby scripts/configure-diagnostics.rb
```

The canonical script requires its Python requirements and the `xcodeproj` Ruby
gem. The overlay preserves synchronized source-group membership, excludes
app-owned Firebase adapters from the local target, and adds the local app-test
scheme. Debug/Release/Internal test configurations retain the app host and mirror
the corresponding app compilation flags. Two complete repeated applications
produced no file changes, including after the build-9 version update.

```sh
swift test
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStoriesLocal \
  -destination 'platform=iOS Simulator,name=Bedtime Stories iPad QA' \
  -derivedDataPath .build/mz-derived CODE_SIGNING_ALLOWED=NO test
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -configuration Internal -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/audit-local-diagnostics.py \
  .build/mz-derived/Build/Products/Debug-iphonesimulator/BedtimeStoriesLocal.app
```

## Verification on 2026-10-02

- 8 standalone app core tests passed.
- 39 local app tests in 6 suites passed on the iPad simulator. They cover original
  error identity, nested causes, privacy filtering, caller forwarding, logging
  once at failure boundaries, cancellation, local cloud isolation, and a live
  UIKit shake callback presenting/dismissing the console.
- The device `Internal` build succeeded without signing.
- All 39 app tests also passed in optimized `Internal` on the iPhone simulator,
  including the PCC compilation gate and covered-book playback regression.
  `ENABLE_TESTABILITY=YES` was an invocation-only test override.
- The local dependency graph and every Mach-O in the app bundle were audited:
  Pulse is present, and remote SDK matches are absent.
- On the iPhone simulator, Settings opened Pulse, Developer Mode persisted,
  enable/disable links worked, and disabling closed the Settings console.
- A disposable invalid recording produced `AVFoundationErrorDomain` / `-11800`
  with nested `NSOSStatusErrorDomain` / `1954115647`. Pulse displayed both causes,
  `StoryPlayer.swift`, the caller line, and a reporting stack. The fixture was
  removed after verification. Screenshot: `.build/mz-setup/pulse-error-details.png`.
- Physical-device motion and provider delivery were not exercised.

The canonical source verifier flags direct vendor imports in the existing
device-only adapters because it does not inspect native target membership. The
canonical binary helper scans only the app executable and debug dylib; Xcode
links Pulse dynamically for these app tests. The app's audit script also scans
embedded frameworks and test bundles. Detailed checks are recorded in
`validation.json`, with raw build/test/audit logs under `.build/mz-setup/`.
