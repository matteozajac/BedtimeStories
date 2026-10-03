# Internal narration enablement — 2026-10-03

The user authorized configuring the remaining Apple/Firebase settings and preparing an enabled Internal TestFlight build. The single backend remains `gen-lang-client-0154884984` (**Always Near Stories**).

## Candidate

Internal **1.0 (10)** is archived and exported with Internal-only export options. The exported IPA verifies the exact bundle/team, enabled narration, Firebase Apple app/project and named private audio bucket. Its distribution signature/profile grant Sign in with Apple, production App Attest, Private Cloud Compute and production CloudDocuments access to the existing iCloud container.

- IPA SHA256: `6e7f214832f466b585fe246be4adf0b1a63d7fec392a78fbc2d4267c1af05e32`.
- Release input fingerprint: `cf6b78473b50fac39e4a5308c04f9a8149ac80b6b88563f4ee193a080a3e7c2e`, 125 inputs, including the ignored public Firebase client configuration.
- Profile UUID: `5abe4610-98c2-404b-89ee-2d87f303e113`, expires 2027-08-09.
- Minimum OS: iOS/iPadOS 27.0.
- Validation: 39 native tests in the isolated Local target's optimized Internal configuration; 8 Swift Testing core tests; 3 snapshot XCTest tests. Main app device archive/export and signature/configuration checks passed. Local binary isolation passed, and repeating the configuration script preserved the release input fingerprint.

The main app's Internal configuration alone sets `BEDTIME_CLOUD_NARRATION_ENABLED=YES`. Other configurations and the isolated Local target set it to `NO`. The public client configuration is ignored by Git; administrative credentials and Gemini access remain server-side.

## Provider and Apple checkpoint

Using the deployed worker's actual service account and immutable worker image, `gemini-3.8-flash-tts` generated a 4.48-second mono 24 kHz WAV (222,698 bytes) with the prebuilt Kore voice and a warm/reassuring style. HTTP 200 and completed Cloud Run execution `bedtime-tts-access-probe-45dkt` were verified. The temporary job was deleted and its absence read back. This checks model access and audio format, not a parent's voice replication or perceptual emotional quality.

Safari saved and freshly read back Services ID `com.matteozajac.bedtimestories.signin` (Apple resource `5VP9FM6T2H`), primary app `4TCJLR98Y5.com.matteozajac.bedtimestories`, domain `gen-lang-client-0154884984.firebaseapp.com` and return URL `https://gen-lang-client-0154884984.firebaseapp.com/__/auth/handler`.

The confirmed app-only **Always Near Stories Apple Sign In** key was registered as `3U65Q87365`. Its sole capability is Sign in with Apple for this primary app. The downloaded private key was saved and verified in macOS Keychain (service `com.matteozajac.bedtimestories.apple-signin`, account `3U65Q87365`), then the plaintext download was removed. Firebase's managed Apple code-flow configuration was updated through the authenticated Identity Toolkit API. Fresh readback verifies provider enabled, exact Services ID/bundle/team/key ID and private key configured. No private key or administrative credential is in Git or release receipts.

Safari confirms App Attest **Registered**, and Storage/Firestore App Check **Enforced**. Authentication's preview App Check product remains unenforced; private callables enforce and consume limited-use App Check tokens in code.

## Enabled deployment and distribution

The user authorized enabling this Internal beta. All nine Functions were redeployed with `ENABLE_CLOUD_NARRATION=true`; fresh Cloud Functions readback confirms each **ACTIVE**, the intended API service account and enabled value. An unauthenticated private worker request returned **403**, and an unauthenticated narration request returned **401** after activation. Existing private bucket/IAM and owner-scoped rules remain in place.

Internal **1.0 (10)** is uploaded and processed: build `54d844e5-c515-461b-927b-0f70d323216c`, **VALID / INTERNAL_ONLY / IN_BETA_TESTING**. Effective access lookup is complete for existing **Internal Testers** (`20328e88-9f9c-4c47-be78-c33a809d1a71`, explicit and all-build access). English notes `82a62a3e-8ffa-4268-92a5-05ecba33ebe4` match the uploaded text. Safari independently shows build 10 **Testing**, Internal Testers and two invites, with no installation yet. Both existing tester records remain `INSTALLED`; that state does not prove installation of this build.

Raw release/readback receipts are retained under ignored `.build/pti/1.0-10/`; protected provider readbacks remain outside Git. See [TestFlight receipt](TESTFLIGHT.md).

Real-device Apple sign-in/App Attest, microphone, parent voice create/reuse/style/deletion and live two-account isolation remain acceptance checks for the enabled beta.
