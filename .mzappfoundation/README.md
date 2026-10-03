# App diagnostics

BedtimeStories uses MZAppFoundation **0.5.1**, resolved to
`4c882c99e6c6aec87b7b8990f8ce711bef72744e`, with Firebase **12.19.2** and Pulse **5.2.1**.

## Console, keyboard help and bug reports

Enable **Settings → Developer → Developer Mode**, then shake the device,
press **Command-D** on a connected keyboard, or choose **Open Logs**.
The package presents tools in a temporary window above existing sheets and alerts.
Closing tools restores the original presentation and unfinished app state.
**Keyboard Shortcuts** remains available with developer mode disabled.
The app has no reader keyboard bindings to list; apps can inject implemented
shortcuts into the shared help component.

**App Foundation** provides version/build information, provider inspection,
startup history, counters, the reporting console and recording preferences.
The console's Ladybug action prepares a ZIP containing the screenshot, Pulse logs,
Foundation diagnostics, schema-2 manifest, optional recent silent screen recording
and an optional voice message. All capture and files stay local until shared.
The recent-activity buffer is bounded to 60 seconds and can be disabled in the
recording page. ReplayKit and voice recording use the system's consent UI.
Developer mode revocation closes tools and waits for pending exports before cleanup.

Use `bedtimestories://developer/enable` and `bedtimestories://developer/disable`.
Disabling also closes the tools. Bundle-host routes and shared `mzappfoundation`
links are retired: Apple does not define which app opens a scheme registered by
multiple apps. Book file imports retain their existing handling.
Local/Debug/Internal builds default to enabled; production defaults to disabled.
A saved developer preference wins over the build default.

## Provider and logging ownership

The device app retains Firebase Auth/App Check/Firestore/Functions/Storage for
Cloud Narration. `AppFoundationDiagnostics` passively reads the bundled Firebase
configuration, SDK version, and current project/app identity. Cloud Narration owns
initialization. Foundation adds no Analytics adapter and does not initialize SDKs
when inspecting configuration. RevenueCat and Sentry remain unconfigured.

The local app bundles no Google configuration and links no remote SDKs.
`AppDiagnosticServices` supplies the app's existing Pulse logger, which avoids
synchronous metadata repair and preserves readable errors, structured causes,
caller locations and bounded reporting stacks. Story content, credentials and
raw provider messages are excluded from log metadata. Screenshots and recordings
can contain visible content; inspect the report before sharing.
Remote analytics and diagnostics remain disabled. No backend deployment or new
provider resource is part of this upgrade. See [logging](../docs/LOGGING.md).

## Repeatable setup and verification

```sh
python3 /path/to/MZAppFoundation/scripts/setup.py apply --app-root .
ruby scripts/configure-diagnostics.rb
swift test
```

The setup script requires its Python requirements and the `xcodeproj` Ruby gem.
The app overlay preserves synchronized source membership, excludes device-only
Firebase adapters from `BedtimeStoriesLocal`, configures hosted tests, and restores
the app-owned inspector/logger in the generated bootstrap. The generic source
verifier flags these deliberate overrides and direct vendor imports; native
target builds and the full-bundle isolation audit verify the resulting composition.
Hosted tests disable recent recording before presentation to avoid ReplayKit
consent dialogs in unit tests.

Current evidence is in `validation.json`, with raw logs/results under
`.build/mz-upgrade-0.5.1/` and release artifacts under `.build/pti/1.0-13/`.
The previous 0.5.0 and 0.3.1 validation records are preserved separately.
Physical Magic Keyboard, accelerometer, ReplayKit, microphone, iCloud and provider
acceptance remain distinct from automated simulator and signed build evidence.
See [Internal TestFlight receipts](../docs/TESTFLIGHT.md).
