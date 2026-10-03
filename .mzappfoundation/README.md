# App diagnostics

BedtimeStories uses MZAppFoundation **0.5.0**, resolved to
`888e5f6c2423109e99d4b4eab670cfebca9cb051`, with Firebase **12.19.2** and Pulse **5.2.1**.
The app version and build number are unchanged by this package upgrade.

## Opening the console

- Enable **Settings → Developer → Developer Mode**, then shake the device.
- **Settings → Developer → Open Logs** provides a navigation fallback.
- **Settings → Developer → App Foundation** opens the library's version,
  provider details, build information, startup history, counters, and developer
  tools pages. Both entries disappear when Developer Mode is disabled, and
  disabling also dismisses the Foundation screen.
- `mzappfoundation://com.matteozajac.bedtimestories/developer/enable` and
  `mzappfoundation://com.matteozajac.bedtimestories/developer/disable` are the
  canonical routes. The app-host routes also support the `bedtimestories` scheme.
- `bedtimestories://developer/enable` and `bedtimestories://developer/disable`
  control the same persistent preference. Disabling also closes the console.
- Local/Debug/Internal builds default to enabled; production defaults to disabled.
  A saved choice wins over the build default.

Existing developer controls have English and Polish app translations. The new
Foundation screens use the library's English presentation. The shared persistent
developer key migrates the existing app-specific choice. Book file imports retain
their existing handling. The console uses MZAppFoundation's scoped UIKit shake
responder, without app-wide swizzling.

## Provider inspection

The device app retains Firebase Auth/App Check/Firestore/Functions/Storage for
Cloud Narration. `AppFoundationDiagnostics` passively reads the bundled Firebase
configuration, SDK version, and current project/app identity. Cloud Narration
continues to own initialization; Foundation reports external ownership and does
not add an Analytics adapter. Inspection does not initialize SDKs or send events;
it reads current runtime state when a snapshot is requested.

The local app bundles no Google configuration and links no remote SDKs. Firebase
details report **Missing configuration** and **SDK not linked**. RevenueCat and
Sentry remain unconfigured. Resolved versions in build information describe the
project lockfile; they do not mean every package is linked or initialized locally.

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
| `BedtimeStories` | Device app. Retains app-owned backend SDKs and uses local Foundation services without remote telemetry adapters. `Internal` enables developer mode by default. |

Both app targets generate `MZFoundationBuildMetadata.plist` after resources are
copied, recording the resolved Foundation version/revision, package versions,
build channel, and app source identity.

Use the canonical setup script, then the app overlay, in this order:

```sh
python3 /path/to/MZAppFoundation/scripts/setup.py apply --app-root .
ruby scripts/configure-diagnostics.rb
```

The canonical script requires its Python requirements and the `xcodeproj` Ruby
gem. The overlay preserves synchronized source-group membership, excludes
app-owned Firebase adapters from the local target, adds the local app-test scheme,
and injects the app-owned passive inspector into the generated device inventory.
Debug/Release/Internal test configurations retain the app host and mirror the
corresponding app compilation flags. Two complete repeated applications after
this upgrade produced no file changes.

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

## Verification on 2026-10-03

- 8 standalone app core tests passed.
- 39 local app tests in 6 suites passed on the iPad simulator. They cover original
  error identity, nested causes, privacy filtering, caller forwarding, logging
  once at failure boundaries, cancellation, local cloud isolation, and a live
  UIKit shake callback presenting/dismissing the console.
- The device `Internal` build succeeded without signing, including the passive
  Firebase inspector and existing private cloud compute compilation gates.
- Every Mach-O in the local app bundle was audited: Pulse is present, and remote
  SDK matches are absent.
- Built local and device metadata both report Foundation 0.5.0 and its exact
  release revision. The device Firebase plist remains bundled; the local app has none.
- A Maestro flow on the iPhone simulator verified the version screen, missing
  Firebase configuration, shared enable/disable links, the app-scheme canonical
  enable route, the legacy disable route, and dismissal/hiding on developer disable.
  The simulator's original enabled developer preference was restored.
- Setup apply plus the app overlay were repeated twice without changing files.
- Physical-device motion, device Firebase runtime inspection, and provider delivery
  were not exercised. This upgrade did not upload a TestFlight build.

The subsequent logging release passed 47 native app tests and 8 core tests,
verified readable Pulse error stacks, and shipped Foundation 0.5.0 in Internal
1.0 (11). Backend logging deployment and smoke checks also passed. See
[logging diagnostics](../docs/LOGGING.md) and [release receipt](../docs/TESTFLIGHT.md).

The canonical source verifier flags direct vendor imports in the existing
device-only adapters because it does not inspect native target membership. The
canonical binary helper scans only the app executable and debug dylib; Xcode
links Pulse dynamically for these app tests. The app's audit script also scans
embedded frameworks and test bundles. Current checks are in `validation.json`,
with logs, the UI flow, metadata, and screenshots under `.build/mz-upgrade-0.5.0/`.
The prior 0.3.1 validation, including its historical TestFlight receipt, is
preserved in `validation-0.3.1.json`.
