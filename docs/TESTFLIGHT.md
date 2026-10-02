# Internal TestFlight

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
