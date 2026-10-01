# Internal TestFlight

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
