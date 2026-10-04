# Internal TestFlight

## 1.0 (18) — 4 October 2026

Background operations and the physical-device runtime follow-up are available to **Internal Testers**. Exact readback confirms **VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective group access, and matching saved English/Polish What to Test notes.

- Build/upload ID: `b4c883fa-388e-458e-82cf-7c93c56d21e9`.
- App: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Notes: English `38f972e7-23df-4f70-9cd3-1e998ab110ee`; Polish `24eb7e2d-d22d-4f4e-9f00-299e5124c996`.
- Minimum iOS/iPadOS, compatible Mac and visionOS: 27.0.
- IPA SHA256: `b1ffe9ae53d52b107863ae25921c1a6b26dd51a840c2f791e8aaedb4671ae07e`.
- Release input fingerprint: `2ff38ee0601210f4780532ff723d9531c46feac8ce58851e7acc8b23b19c4027`; all 155 inputs matched the final archive/export and distribution source.
- Signed artifact checks passed app/widget identity, version/build, deep signature verification, production APNs/App Attest/iCloud, Apple sign-in, PCC, background identifiers, and the exact Firebase app. Explicit manual app/widget profiles match the build-17 receipt and expire 5 March 2027. Export is Internal-only.

Close now keeps an editing draft while narration continues. Explicit Discard separately cancels related operations and retains durable receipts against late cloud results. Older deleted drafts expose available owned audio through a listen-only recovery screen, including cold notification taps before cloud metadata arrives. Repeated discard and failed deletion are protected. Backend Live Activity registration succeeds independently of delivery; its private outbox retries within an eight-hour expiry when APNs is unavailable.

Validation: **103 integrated Internal local app tests** passed, followed by **17 creator tests** after the final repeated-discard guard. The original close/discard regression and repeated-discard edge both failed before their corrections. Local SDK isolation passed. Seeded iPad editor checks passed **4/4 in English and 4/4 in Polish**, retaining and reopening the same real editing draft while a seeded narration stayed running. Backend validation passed **29 unit + 42 emulator tests**. The previously validated **58 worker**, **9 core**, **6 authoring** tests, six real English/Polish Gemini storyteller probes, and private no-op queue probe remain applicable because their source did not change in this follow-up.

The five affected functions are ACTIVE; private trigger invocation grants were preserved, and the pending-delivery index is READY with a successful read-only production query. See [runtime diagnosis and regression evidence](BACKGROUND_OPERATIONS_QA_FIXES.md) and [backend deployment evidence](BACKGROUND_OPERATIONS_BACKEND.md).

The generic strict TestFlight validator reports four missing beta-review contact fields (first/last name, email, phone). These external-review metadata gaps remain unchanged; the exact Internal-only build is already IN_BETA_TESTING with confirmed group access and saved notes. No external beta or App Store review was submitted.

The owner explicitly deferred Firebase APNs credential setup. Remote notification delivery and server-driven suspended/terminated-app Live Activity updates remain pending that setup and physical-device validation. In-app banners and local-operation alerts are implemented. Existing tester states do not establish installation of build 18; the supplied physical-device log identifies build 17. Raw logs, private audio, credentials, state and release artifacts remain outside Git in protected/ignored locations.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (17) — 4 October 2026

Durable background operations, completion banners/deep links, the Settings operations list, Live Activities, and three built-in storytellers each for English and Polish are processed and available to **Internal Testers**. Exact readback confirms **VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective group access, and matching saved English/Polish What to Test notes.

- Build/upload ID: `971365f6-eec4-49ed-9497-a600e483ca77`.
- App: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Notes: English `0e433536-dd7d-4580-8084-5cbb16f2fd87`; Polish `ddba311c-4ed2-4cef-bcbb-17c481796174`.
- Minimum iOS/iPadOS, compatible Mac and visionOS: 27.0.
- IPA SHA256: `9692b79592bf832d877d4e02382e0fef6337a1e7be5dd5489ff218da4bc93e9c`.
- Release input fingerprint: `e2f83102ba2619369f4dce6d0a1d95bb133ec9715517d7bfe223ec7e4c2d129b`; all 153 inputs matched the final archive/export and distribution source.
- The signed artifact verifies production APNs, the embedded `com.matteozajac.bedtimestories.operations` ActivityKit widget, permitted continued-processing identifiers, matching Firebase identity, production App Attest/iCloud, Apple sign-in, and PCC. Internal uses `PrivateCloudCompute.entitlements`; its push entitlement is included explicitly.
- Export uses explicit manual profiles after automatic signing timed out: app `39d41d49-9646-441c-af80-06f1cf3de91f`, widget `d1084a6b-7d9c-40f4-babd-1488c1fef7af`; both expire 5 March 2027. Internal-only export and version/build 1.0/17 were verified before upload. An upload discovery timeout was resolved by reading the existing processed build; no second upload was needed.

Validation passed **91 native app tests**, the final **21 operation tests**, **28 backend unit + 40 emulator tests**, **58 worker tests**, **9 core tests**, **6 authoring tests**, and the Local binary SDK isolation audit. Seeded iPad UI checks passed six scenarios in each language, including exact-book banner/list/URL navigation and the Settings entry. Six real Gemini requests produced valid English/Polish audio for every shipped storyteller. A live no-op Cloud Task returned HTTP 204 through the private API identity, created no documents/provider calls, and was removed after success.

Functions, Firestore rules/indexes, the immutable worker revision, queue and event invocation permissions, and protected Terraform state were deployed/reconciled and read back. See [the operation audit](BACKGROUND_OPERATIONS.md), [backend evidence](BACKGROUND_OPERATIONS_BACKEND.md), and [Polish UI evidence](qa/operations-evidence-pl.json). Existing story-generation repair changes are included.

Both existing tester records are INSTALLED. A subsequent physical-device log confirms build 17 and exposes draft deletion on Close plus rejected Live Activity delivery; see [the runtime follow-up](BACKGROUND_OPERATIONS_QA_FIXES.md). This candidate is superseded by build 18. The owner deferred Firebase APNs credential configuration. Real remote notification delivery, suspended/terminated-app Dynamic Island updates, microphone/App Attest, cross-device iCloud behavior, and voice quality remain physical-device acceptance checks. No external beta or App Store review was submitted. Secrets, staged recording/audio probes, state, archives, and raw receipts remain outside Git in protected/ignored locations.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (16) — 4 October 2026

The iCloud Edit Book repair and provider diagnostics are processed and available
to **Internal Testers**. Exact readback confirms **VALID / INTERNAL_ONLY /
IN_BETA_TESTING**, complete effective group access and matching English notes.

- Build/upload ID: `edcabda0-71f9-4131-9195-7619f55960ea`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `a1f7b536-d209-4e4f-853e-ba00d9777ef3`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- IPA SHA256: `17aa5d78113fc570fad0927795ab71baab69bb49b441bda22c1b2562a6488663`.
- Release input fingerprint: `b26630ed56f0c48080c383336a282cc4cf8734fe774ebf7b006c76c3f35f7a55`; all 136 inputs matched through final archive, export, upload and distribution.
- Signed Internal archive/export passed strict signature, bundle/version/build, Firebase identity and entitlement checks. Production iCloud, Apple sign-in, App Attest and PCC remain enabled. Export is Internal-only; profile `5abe4610-98c2-404b-89ee-2d87f303e113` expires 9 August 2027.

Every provider query now clears cached URL attributes, so a completed download
can become visible to checkout. Failures retain the asset/chapter, failing phase,
fresh provider state, quota/authentication/server codes and underlying errors.
The shared download repair also applies to asset loading, offline preparation,
import and sharing. See [diagnosis and regression evidence](ICLOUD_EDIT_VALIDATION.md).

Validation: **63 optimized Internal app tests passed on each iPhone and iPad
simulator**, plus **9 core tests**, **6 Python authoring tests**, and the full
Local binary SDK isolation audit. The checkout regression failed before the
repair and passed afterward. Stale local copies remain protected, and nested
provider errors and cancellation are preserved.

Both existing tester records are INSTALLED; this does not establish installation
of build 16. Retest the affected book on the physical device. Real iCloud downloads
and cross-device edits remain device acceptance checks. No external beta or App
Store review was submitted. Raw evidence remains in ignored `.build/pti/1.0-16/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (15) — 4 October 2026

Gemini story generation for Polish and English is processed and available to
**Internal Testers**. Exact readback confirms **VALID / INTERNAL_ONLY /
IN_BETA_TESTING**, complete effective group access and matching saved English
What to Test notes.

- Build/upload ID: `2afdbb22-8be2-4ce8-ad2d-f9e76d5f2cb4`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `21a87ff5-876f-4f1e-a30f-7122b659f1b8`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- IPA SHA256: `2b11de0be1aa5212107b4184dad6c63aa513e8232bea394f8bc3a2141aa292e9`.
- Release input fingerprint: `49f873eb15085d44f1704b20d7e9925f08b2c08a2161d72243fc6f3fb6ee144b`; all 134 inputs matched through archive, export, upload, distribution and closeout.
- Signed Internal archive/export passed strict signature, bundle/version/build, Firebase identity and entitlement checks. Production iCloud, Apple sign-in, App Attest and PCC entitlements remain. Export is Internal-only; profile `5abe4610-98c2-404b-89ee-2d87f303e113` expires 9 August 2027.

Select **Gemini** in Create from an Idea, sign in with Apple and accept the
processing disclosure. Ideas are sent through the authenticated Firebase
function to Google; complete books open in the existing draft editor. Consent
resets on account change. Polish initially selects Gemini in the enabled
Internal build; Apple processing choices remain explicit. Stop Creating ends
the wait immediately and ignores late responses. Existing editing, pictures,
narration, library saving and sharing remain available.

Validation: **59 optimized Internal app tests**, **9 core tests**, **6 Python
authoring tests**, Local SDK isolation, **19 backend unit tests** and **18
emulator tests** passed. Actual Gemini provider probes validated Polish and
English, including a maximum-duration Polish request after bounded scene
repair. [Deployment and validation receipt](GEMINI_STORY_GENERATION_DEPLOYMENT.md).

The two existing tester records are INSTALLED; that does not establish
installation of build 15. Physical Apple sign-in/App Attest, account switching
and iCloud sync remain acceptance checks. No external beta or App Store review
was submitted. Raw release evidence remains in ignored `.build/pti/1.0-15/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (14) — 4 October 2026

The narration-screen storybook redesign is processed and available to
**Internal Testers**. Exact readback confirms
**VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective group access
and matching English What to Test notes.

- Build/upload ID: `3da862b0-a7ee-40e1-a0ac-cb4df1585a6b`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `77265d11-9b74-4298-89be-8bfe4c557275`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- IPA SHA256: `49f3d195befe183ae16aae4d1bba437bf4140e8480ff55d0a1b33873f544c0e9`.
- Release input fingerprint: `857acb83c62edfb7c696160b0789c92a6a44e3e2358f8b7b69ca97a0f29def4f`; 132 matching inputs,
  including the ignored Firebase client configuration.
- Signed Internal archive and Internal-only export passed strict signature,
  identity, Foundation metadata, Firebase configuration and entitlement checks.

Updated voice cards, recording steps, style chips, chapter rows, narration
progress cards and account presentation use the app's storybook design. Small
row actions use the shared compact button styles. English and Polish labels
are included. Test voice enrollment and deletion, book/paragraph styles,
preview, progress, cancellation and Use Narration; retest reading, playback,
editing and sharing.

Validation: **55 native app tests in optimized Internal, 9 core tests and 6
Python authoring tests passed**. The full Local binary SDK isolation audit passed.
All release inputs matched through archive, export, upload and distribution.
The general strict TestFlight readiness check reports four missing beta-review
contact fields; exact internal testing and group access are active. No external
review was requested.

The two existing tester records are INSTALLED; this does not establish
installation of build 14. Physical microphone, App Attest, iCloud sync and real
parent-voice quality remain device acceptance checks. Existing backend settings
are retained. Raw receipts and artifacts remain in ignored `.build/pti/1.0-14/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (13) — 3 October 2026

MZAppFoundation 0.5.1, shared keyboard help, Command-D console access and the
Ladybug ZIP reporter are processed and available to **Internal Testers**.
Exact readback confirms **VALID / INTERNAL_ONLY / IN_BETA_TESTING**, effective
all-build group access and matching English What to Test notes.

- Build/upload ID: `9534afa3-2730-4fa3-ba75-bff2534f52a8`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, existing all-build access).
- English notes: `9f448edb-de2d-4b8e-bf5e-46e8ee25b3f2`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- Foundation: `0.5.1` at `4c882c99e6c6aec87b7b8990f8ce711bef72744e`.
- IPA SHA256: `420fba8f4b318d9e2f4153146574201b2f118b420de99eefafd05c90f720368d`.
- Release input fingerprint: `64784621d0c06fb5af7ad174743336572c79d56e577b9e4d2db9ce54413e0765`; 131 matching inputs,
  including the ignored Firebase client configuration.
- Signed archive and Internal-only export passed strict signature, identity,
  Foundation metadata, app-specific scheme and entitlement checks. Production
  iCloud, Apple sign-in, App Attest and Private Cloud Compute entitlements remain.

Enable **Settings → Developer → Developer Mode**, then press **Command-D**, shake
or select **Open Logs**. The package opens its console above app presentations.
**Keyboard Shortcuts** remains available with developer mode off. Developer links
are `bedtimestories://developer/enable` and `bedtimestories://developer/disable`;
shared and bundle-host routes are retired. The Ladybug opens the report editor;
recording preferences live in **App Foundation → Bug reporting and recording**.

Validation: **55 hosted app tests and 9 core tests passed**, including forwarding
shake above an alert while preserving the alert. Local SDK isolation and two
repeatable setup applications passed. In the iPad simulator, a Mac keyboard
opened the console from a text field and above both Settings and keyboard help;
Done restored keyboard help. A real report export produced an intact schema-2
ZIP with screenshot, Pulse logs and Foundation diagnostics, and developer disable
closed reporting while preserving Settings. Recent capture was disabled for
these automated checks. The package's macOS test runner could not establish its
connection; its build passes, but macOS runtime validation remains open.

Physical Magic Keyboard, accelerometer, ReplayKit, microphone, iCloud and provider
acceptance remain open. The two existing tester records are INSTALLED; this does
not establish installation of build 13. Existing backend configuration and
logging deployment are retained. No provider setup or backend deployment occurred.
Raw evidence is retained under `.build/mz-upgrade-0.5.1/` and `.build/pti/1.0-13/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (12) — 3 October 2026

The whole-app logging audit and readable Pulse text export are processed and
available to **Internal Testers**. Exact readback confirms
**VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective group access and
matching English What to Test notes.

- Build/upload ID: `44c47474-955a-4883-b968-705f521cb0d7`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `89bd9a0c-bf2e-4166-b69a-043e4b8cd119`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- IPA SHA256: `2b9465c0fb3c449adcb29e8f850ac9fa45969bb7577a133e193512f102ad01f6`.
- Release input fingerprint: `182977519eeb2aa3ec681aab1822f8a5fbfdd84107f2c02e0a9677d47fb072ad`; 131 matching inputs, including the ignored Firebase client configuration.
- Signed Internal archive and Internal-only export passed strict signature,
  identity, Firebase configuration, Foundation metadata and entitlement checks.

Copied logs retain operation IDs, phase, asset kind/index, elapsed time, safe
technical explanations, underlying causes, source/capture locations and bounded
stacks. Book editing now traces checkout through iCloud downloads, file-provider
coordination, copying, draft creation and publication. App actions, migrations,
reader/playback, recording, model validation and cloud narration also have
context. The local sink fixes the Foundation 0.5.0 synchronous Pulse metadata
repair deadlock while preserving readable structured frames. Diagnostics issue
codes and remote consent behavior remain unchanged.

Validation: **55 native app tests and 9 core tests passed**, including observed
console saves, plain-text persistence/privacy, checkout success/failure,
underlying error evidence and Gemini code explanations. Local binary isolation,
setup syntax/hooks and secret scans passed. A representative filesystem failure
was inspected in Pulse message text and Info, with source and readable stacks.
See [logging evidence](LOGGING.md).

Test editing an iCloud book and copying any failure from Settings → Developer →
Open Logs. Also retest importing/sharing, media attachments, reader/playback and
voice/narration failures. The two existing tester records remain INSTALLED;
this does not establish installation of build 12. Real iCloud/provider/device
acceptance remains open. The existing backend logging deployment from build 11
is retained; this release changes app logging.

Raw release receipts are retained in ignored `.build/pti/1.0-12/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (11) — 3 October 2026

The MZAppFoundation 0.5.0 upgrade and expanded app/Gemini/connection logging are
processed and available to **Internal Testers**. Exact readback confirms
**VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective group access and
matching English What to Test notes. Cloud narration remains enabled for this
Internal build against the existing shared backend.

- Build/upload ID: `6fb981c9-1f28-451b-81ef-454d8b825146`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `d70c6006-da9e-4ad2-b57a-f1cd87a5703b`.
- Minimum iOS/iPadOS, compatible Mac and Vision OS: 27.0.
- IPA SHA256: `3c022f284424067afdebb048049bdd3e71c479fc6222b77072193459d29fbaa5`.
- Release input fingerprint: `33a9dc4d75414b1ca9ba3213f919d8086a1e9eecea9f16b9bf571db38a2934fc`; 128 matching inputs, including the ignored Firebase client configuration.
- Signed Internal archive and Internal-only export passed strict signature,
  identity, Firebase configuration, Foundation metadata and entitlement checks.
  Apple sign-in, production App Attest, PCC and the exact production iCloud
  container were verified in the exported app.

Validation: 8 Swift core tests, 47 native app tests, 52 worker tests and 10 Functions
tests passed. Local binary isolation passed. All nine Functions are ACTIVE on
new revisions; the private worker serves revision `bedtime-voice-worker-00003-gcr`
at 100% traffic. A harmless deployed error probe verified original exception
frames in Cloud Logging, and the recovery scheduler verified DEBUG Firestore
connection traces. See [deployment readback](CLOUD_NARRATION_DEPLOYMENT.md).

Test voice enrollment, narration, playback and failed/offline connections; open
Settings → Developer → Open Logs, select an error and inspect Info for stacks.
Also test draft saves, recording, library sync and recovery. The two existing
tester records remain INSTALLED; this does not prove installation of build 11.
Physical-device and real parent-voice acceptance remain open.

Raw release receipts are retained in ignored `.build/pti/1.0-11/`.
[Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (10) — 3 October 2026

Cloud narration is enabled for this Internal beta against shared **Always Near Stories** Firebase project `gen-lang-client-0154884984`. Apple sign-in/code-flow credentials are configured, App Attest is registered, and all nine Functions are ACTIVE with narration enabled. Exact readback confirms **VALID / INTERNAL_ONLY / IN_BETA_TESTING**, complete effective Internal Testers access and matching English What to Test notes. Safari independently shows build 10 Testing with two invites and no installs yet.

- Build ID: `54d844e5-c515-461b-927b-0f70d323216c`.
- App ID: `6818278413`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- English notes: `82a62a3e-8ffa-4268-92a5-05ecba33ebe4`.
- Minimum OS: iOS/iPadOS 27.0; compatible Mac/Vision minimums also read back as 27.0.
- IPA SHA256: `6e7f214832f466b585fe246be4adf0b1a63d7fec392a78fbc2d4267c1af05e32`.
- Release input fingerprint: `cf6b78473b50fac39e4a5308c04f9a8149ac80b6b88563f4ee193a080a3e7c2e`, 125 matching inputs including ignored public Firebase client configuration.
- Signed Internal archive/export and strict signature/configuration verification passed. Exported entitlements include Apple sign-in, production App Attest, PCC and Production CloudDocuments for the existing iCloud container. Profile `5abe4610-98c2-404b-89ee-2d87f303e113` expires 9 August 2027.

Validation: 39 native tests on the isolated Local target's optimized Internal simulator configuration, 8 Swift Testing core tests, 3 snapshot XCTest tests, 6 Python authoring tests and Local binary isolation passed. The main app's device archive/export compiled the Firebase implementation. The actual worker identity generated mono 24 kHz prebuilt Kore audio using fixed `gemini-3.8-flash-tts` (HTTP 200); public worker and unauthenticated narration requests returned 403/401.

Install this build and test Settings → Your Voices: genuine Apple sign-in/App Attest, consenting parent's recordings and voice approval, chapter/book generation and styles, cancellation/relaunch, deletion and switching between two accounts. Real parent likeness/emotion, physical microphone, Apple/App Attest and deployed two-user denial are still acceptance checks. Both existing tester records remain INSTALLED; this does not establish installation of build 10. Administrative/Gemini/Apple credentials are absent from the app and Git. No tester membership or external/App Review submission changed.

[Detailed activation receipt](CLOUD_NARRATION_INTERNAL_ENABLEMENT.md). Raw release evidence remains in ignored `.build/pti/1.0-10/`. [Open TestFlight](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (9) — 2 October 2026

The MZAppFoundation 0.3.1 logging integration and playback artwork crash fix are
processed and available to **Internal Testers**. Exact readback confirms `VALID`,
`INTERNAL_ONLY`, `IN_BETA_TESTING`, complete effective group access, and English
What to Test notes matching the uploaded text.

- Build/upload ID: `fd7a31d7-7573-44fb-941f-f3f0a7adb08f`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Minimum OS: iOS / iPadOS 27.0; compatible Mac/Vision minimums also read back as 27.0.
- Configuration: **Internal**, optimized and without the invocation-only testability override.
- IPA SHA-256: `ca785a582e51ef1e7b039cbacad4c05a8024c52519bde7f843c0e7be32369765`.
- Release source fingerprint: `615876351a38bd828139155b1709e9f2e7e98cb244c71ee42cf23149af23d7e8`; all **123 release input hashes** matched through archive, export, upload and processing.
- Signed archive and Internal-only export passed. The app's signature and embedded App Store profile grant Sign in with Apple, production App Attest, Private Cloud Compute and **Production** CloudDocuments access to the exact iCloud container. Profile UUID remains `5abe4610-98c2-404b-89ee-2d87f303e113`, expiring 9 August 2027.
- English test-note localization: `bafb7ffd-d02a-4776-bb58-67a52714ff9b`.

Developer Mode defaults on in this Internal build unless explicitly disabled
before. Shake opens Pulse; **Settings → Developer → Open Logs** is the fallback.
Structured error logs preserve error identity, nested causes, caller information
and reporting stacks while omitting story content, recordings, and paths. Remote
analytics and diagnostics remain disabled. The MediaPlayer artwork and remote
command callbacks now safely run on system background queues. Retest covered-book
playback, including the iOS-compatible app on Vision Pro.

Validation: **39 native tests in six suites passed in optimized Internal** on
the iPhone simulator, including the artwork regression, PCC compilation gate,
structured logging and UIKit shake callback. **8 Swift Testing core tests, 3
snapshot XCTest tests and 6 Python authoring tests** passed. Local binary isolation
passed, and two repeated setup applications produced no changes. See
[diagnostics](../.mzappfoundation/README.md) and [playback regression](PLAYBACK_CRASH.md).

Cloud narration remains disabled, with no Firebase client configuration bundled.
Existing local/iCloud books, manual recording and Apple AI flows retain their
existing requirements. Build availability does not establish installation or
physical-device shake/playback behavior. Raw release receipts, signatures and
the input fingerprint are in `.build/pti/1.0-9/`; they are disposable outputs and
are excluded from Git.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (8) — 2 October 2026

The parent-voice client and privacy implementation is processed and available to **Internal Testers**. Exact readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, complete effective group access, and saved English What to Test notes matching the upload (Apple trims the terminal newline).

- Build/upload ID: `0b69f792-f2ac-4c37-b3d9-f5dd83cfdc73`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Minimum OS: iOS / iPadOS 27.0.
- IPA SHA-256: `200b6dfdfe44cd199035cd1c90f2f5c35269d4f6b543d03c8f5bc04a8731fa35`.
- Release source fingerprint: `4f4dbbbc67839f25d0dee011e15f8d578a5863e401a918362fed1f9d9e29c860`; all **113 release input hashes** matched before/after archive, export, upload and processing.
- Signed archive and Internal-only export passed. Exported app identity, device families, signature/certificate and profile were verified. The signature grants Sign in with Apple, production App Attest, Private Cloud Compute and **Production** CloudDocuments access to `iCloud.com.matteozajac.bedtimestories`.
- Refreshed automatic App Store profile: **iOS Team Store Provisioning Profile: com.matteozajac.bedtimestories**, UUID `5abe4610-98c2-404b-89ee-2d87f303e113`, profile expiry 9 August 2027. The reused Apple Distribution certificate expires 5 March 2027.

**Cloud narration remains disabled** in this binary, and no Firebase client configuration is bundled. Settings → Your Voices explains availability; enrollment and generation cannot begin. Dedicated Google project creation was rejected because the account project quota is full. The backend, encryption, owner isolation, deletion/recovery and Gemini 3.8 worker implementation are included in source, with deployment and live provider/device validation still pending. Existing local/iCloud book creation, manual narration, reading, playback, sharing and Apple AI features remain available under their existing requirements.

Validation: **32 native tests in 4 suites passed in Release**, with no failures/skips, including account switching/cancellation during audio attachment, recording duration limits and private request-retry receipts. Implementation checks also passed: **3 narration snapshot XCTest tests + 8 Swift Testing core tests**, **6 Python authoring tests**, **6 Functions unit tests**, **12 Firestore/Storage isolation scenarios**, **44 worker tests** and **6 infrastructure helper tests**. Terraform schema/format validation, dependency audits and source hygiene passed. See the [cloud narration receipt](CLOUD_NARRATION_VALIDATION.md).

Both existing testers remain `INSTALLED` and report build 1.0 (7), so installation of build 8 is not established. Physical-device microphone, Apple/App Attest authentication, generated voice likeness/emotion, deployed A/B denial and cloud deletion checks remain pending. No tester membership changes or external/App Review submission were made.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (7) — 2 October 2026

The editing, reading-duration, and Image Playground update is processed and available to **Internal Testers**. Exact readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, complete effective group access, and English What to Test notes matching the upload.

- Build/upload ID: `31c4c04d-fd19-4de3-8f03-58a6e679478e`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Minimum OS: iOS / iPadOS 27.0.
- IPA SHA-256: `41d46cf7440cfdc556fec86af9d4ea6344c4f18fc1a9412d310e4949bfd1d0c2`.
- Release source fingerprint: `8372647f1e3a8e30bf9f9a58566c9e87ddc0d7a8d80a1ae57e669b7c93f536f1`; all **83 release input hashes** matched through archive, export, upload and processing.
- Signed archive, optimized PCC compilation flag, Internal-only export, app identity, signature, certificate, profile, and device families were verified. The signature and embedded profile grant PCC and Production CloudDocuments access to the exact iCloud container. Profile UUID remains `3af35bdd-ce98-4c8a-bd6a-03cf35d8aaa7` (expires 5 March 2027).

**Edit Book** opens a complete local working copy of an existing book with stable book/chapter identities. Save coordinates replacement after checking a content fingerprint; conflicts preserve edits and offer Save as a New Book. Pinned books receive a complete updated offline copy in the same save transaction. Text, images, recordings, chapter addition/reordering/removal, full-book narration and existing timestamps are supported. Save publishes/closes; Discard confirms session rollback; Close appears when unchanged.

AI creation now uses whole-book reading minutes and words/minute. A duration-specific schema chooses a sensible chapter-count range, and total prose is checked against 80–120% of the target. Invalid output receives one fresh complete-book retry with measured length guidance. On-device creation supports up to 600 target words; longer books, including 20 minutes at 120 words/minute, require explicitly selecting PCC. Image Playground receives prepared scene prompts, shared appearance/style, and optional cover references; the person reviews and accepts images before saving the book.

Validation: **27 native tests passed in Release on iPhone and Debug on iPad**, including an offline edit readback after deleting the source folder. **8 Swift core tests** and **6 Python authoring tests** passed. Real local-model checks produced complete two- and five-minute books in one response each (217 and 549 words at 120 words/minute). English iPhone UI verified edits, discard, chapter addition, save and reopen; Polish iPad UI verified the 20-minute/2400-word controls. [Detailed validation](AI_CREATOR.md).

The user reported successful PCC creation with build 6. Physical 20-minute PCC generation, Image Playground image acceptance, real microphone quality and simultaneous iCloud edits on two devices remain hardware checks for this version. Both existing testers remain `INSTALLED`; their reported builds are iPhone 1.0 (6) and Vision Pro 1.0 (4), so installation of build 7 is not yet established. No membership changes or external/App Review submission were made.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (6) — 2 October 2026

The PCC-enabled signed build is processed and available to **Internal Testers**. Exact-build readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, complete effective group access, and saved English What to Test notes matching the upload.

- Build/upload ID: `6a732e8e-4a49-4313-8bf8-f7fe560d5a00`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, explicit and all-build access).
- Minimum OS: iOS / iPadOS 27.0.
- Profile generated/downloaded in Safari: **Always Near Stories PCC App Store 2026-10-02**, UUID `3af35bdd-ce98-4c8a-bd6a-03cf35d8aaa7`, expires 5 March 2027. It reuses the installed personal Apple Distribution certificate.
- IPA SHA-256: `c8aed0081fe162392e843e31d99e46cf8130d932ebea2835e1ea3f4063e2ceb5`.
- Release source fingerprint: `41b7bd60b77e930ca7edcccb63e0d767ea38d46c3909ac2a2ee1ee20e7ad9ec6`; all **76 release input hashes** matched through archive, export, upload and processing.

Apple's approved PCC capability was saved and read back on this App ID. Release now includes `BEDTIME_PRIVATE_CLOUD_COMPUTE` and the merged PCC/iCloud entitlements; Debug remains local-only. The exported signature and embedded App Store profile both grant Boolean `com.apple.developer.private-cloud-compute`, and the app retains **Production** CloudDocuments access to `iCloud.com.matteozajac.bedtimestories`. Bundle, version/build, team, distribution certificate, profile, minimum OS, device families, signature, and Internal-only export options were verified.

The whole-book generator, output validation/retry, and automatic library from build 5 remain in place. **On This Device** remains selected by default; cloud generation requires explicit selection, eligible hardware, Apple Intelligence, internet, a supported language, and quota. The app-version PCC gate is now enabled in this Release build. Successful PCC inference, speed/quality, and physical iCloud behavior still require testing on an eligible iPhone/iPad.

Validation: unsigned Release device compilation and the ordinary signed archive/export passed. All **20 native tests passed in Release and 20 in Debug** on the dedicated iPhone simulator, including both compilation-gate branches; Release tests used an invocation-only testability override. All **6 Python authoring tests** passed. The two existing tester records remain `INSTALLED`, which does not prove installation of build 6.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (5) — 2 October 2026

The complete-book generator and automatic iCloud library are processed and available to **Internal Testers**. Exact-build readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, effective internal group access, and saved English What to Test notes matching the uploaded text.

- Build/upload ID: `6277121b-b7de-4a10-953e-3ebbced6ee7c`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, all-build access; exact build lookup complete).
- Minimum OS: iOS / iPadOS 27.0.
- IPA SHA-256: `16f6d4b6315b0bba3a229c9b51f7be6f8835ff6c4c3dcfc04bb00ee77d41ebff`.
- Release source fingerprint: `ebd8dbf33c80c42b73203c0bd948dca71382ed9eda7877094ffc943b48c7c16f`; all **76 release input hashes** matched before/after archive and export, upload, processing, and Git closeout.
- Signed archive and Internal-only export passed. Exported app identity, signature, profile, device families, minimum OS, version/build and **Production** iCloud entitlement for `iCloud.com.matteozajac.bedtimestories` were verified.

Creates all requested chapters in one response, validates complete text and chapter count, and retries an invalid response once before saving only a complete new draft. The default **Always Near Stories / Books** library is created after consent with local fallback, coordinated cloud discovery, and copying of previous/local books without deleting originals or replacing changed content. There is no library folder picker. Family sharing uses portable files in Files/AirDrop; folder invitations do not automatically connect another person’s app library.

Validation: 20 native tests passed on iPad and the final fresh iPhone simulator, 8 Swift core tests and 6 Python authoring tests passed. Real local model checks produced complete 1-, 2-, 3-, and 4-chapter books, including recovery from an invalid four-chapter response. A four-chapter simulator UI book was saved, published, survived relaunch, and opened in the reader. See [AI_CREATOR.md](AI_CREATOR.md) and [ICLOUD_LIBRARY.md](ICLOUD_LIBRARY.md).

PCC is not enabled in this IPA: Apple’s entitlement grant and a new entitled distribution are required. Physical-device performance, successful PCC inference, and real iCloud visibility/synchronization remain device checks. The two existing tester records remain `INSTALLED`; this does not establish installation of build 5. No groups/testers were created and no external beta/App Review submission was made.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (4) — 1 October 2026

The Foundation Models book creator is processed and available to **Internal Testers**. Exact-build readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, effective group access and saved English What to Test notes matching the uploaded text.

- Build ID: `247b6a0a-976f-4832-aef0-c1937d23611c`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, all-build access).
- Minimum OS: iOS / iPadOS 27.0.
- IPA SHA-256: `ef73cc8a174d87c862ef8ff56b941a5a601fc1fee2eec23e8ed24aaccf8447ad`.
- Release source fingerprint: `56c3aefe270c97e1ce9f17bb2d22378fdc344d8b6664ee41a05be7ab94775ea4`; all 72 release input hashes remained unchanged through archiving, export, upload and processing.
- The signed archive and Internal-only export succeeded. The exported signature, distribution profile, bundle, version, build number, device families and minimum OS matched the intended app.

Adds **Create from an Idea** with on-device Apple Foundation Models, language and reader-age selection, 1–4 chapters, editable drafts and preservation of completed chapters after cancellation or failure. The ordinary Release build does not enable the PCC compilation condition or include its managed entitlement. Private Cloud Compute remains unavailable pending Apple's grant and entitled-device validation; the opt-in configuration is included in source.

Validation: 14 native tests passed on each dedicated iPhone and iPad simulator, 8 Swift core tests passed, and 6 Python authoring tests passed. A real local model generated a three-chapter draft in the simulator; it survived relaunch, published to a local QA library and opened in the reader. The PCC opt-in device build compiled with signing disabled. Physical-device generation performance, offline behavior, iCloud sharing and successful entitled PCC generation remain separate checks. See [AI_CREATOR.md](AI_CREATOR.md) for evidence and the device checklist.

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

## 1.0 (3) — 1 October 2026

The Book Creator build is processed and available to **Internal Testers**. Readback confirms `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, effective group access and saved English What to Test notes.

- Build ID: `0ec597ed-6b7c-4695-aaf6-8f0f4e6f6837`.
- App ID: `6818278413`; bundle: `com.matteozajac.bedtimestories`; team: `4TCJLR98Y5`.
- Group: `20328e88-9f9c-4c47-be78-c33a809d1a71` (**Internal Testers**, all-build access).
- Minimum OS: iOS / iPadOS 27.0.
- IPA SHA-256: `c4062e8f34be9b41bc239edaf0f90fdc855996e70bf229969bb4b4aca974980d`.
- Signature, embedded profile, version and English/Polish microphone purpose strings verified in the exported IPA. All 55 release input hashes remained unchanged.

Adds local drafts, chapter writing/reordering, cover/chapter photos, audio import and in-app recording with pause/resume, review and acceptance. Created books use the existing reading, playback, offline and sharing format. See [CREATOR.md](CREATOR.md) for use, tests and device checks.

## 1.0 (2) — 1 October 2026

Always Near Stories **1.0 (2)** is processed and available to the **Internal Testers** group.

| Identity | Value |
| --- | --- |
| App Store Connect app | `6818278413` |
| Bundle ID | `com.matteozajac.bedtimestories` |
| Developer team | `4TCJLR98Y5` |
| Build ID | `66905150-19a5-4859-b0a5-ed935634c138` |
| Processing state | `VALID` |
| Internal testing state | `IN_BETA_TESTING` |
| Build audience | `INTERNAL_ONLY` |
| Minimum OS | iOS / iPadOS 27.0 |
| Internal group | `20328e88-9f9c-4c47-be78-c33a809d1a71` |

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6818278413/testflight/ios).

The group has access to all builds, and the effective build-group lookup confirms this build is available to it. Both existing testers, `matteo.zajac@icloud.com` and `matt.zajac.92@icloud.com`, changed from `NOT_INVITED` to `INVITED` after processing. This confirms Apple's invitation state, not receipt of the emails or installation on a device.

## Validation for this upload

- Swift core suite: 8 tests passed, including the unsafe-path parameter cases.
- Python authoring suite: 6 tests passed.
- Native library/playback suite: 3 tests passed on each of the iPhone and iPad simulators.
- Release archive and App Store Connect export succeeded. The export uses `testFlightInternalTestingOnly = true`.
- Exported application signature verified; bundle, version, minimum OS, team and distribution entitlements matched the intended app.
- Release source hashes were unchanged between archiving and upload.
- English What to Test notes were saved and read back from App Store Connect.

IPA SHA-256: `ddd6cc195865f826668f2c502d720f845ef49ade0a59d9cec6a5d2205d275964`.

The uploaded app uses the Always Near Stories display name in English and Polish. It contains the native folder-based reading and audiobook library; voice cloning and premium features remain future ideas.

Physical-device iCloud sharing, real narration, background/Lock Screen playback and AirPlay still need testing. The device checklist and earlier UI evidence are in [VALIDATION.md](VALIDATION.md); those screenshots predate this display-name change.
