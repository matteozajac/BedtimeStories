# Shared cloud deployment — 2026-10-03

The backend is deployed to the user-selected existing Firebase/Google Cloud project **Always Near Stories** (`gen-lang-client-0154884984`, project number `280562253820`). TestFlight and production share this project. The original Via Tales project ID is immutable; both its project and Firebase public-facing names now match the app.

## Deployed resources and readback

| Resource | Verified deployment |
| --- | --- |
| Billing | Blaze; personal Private Projects account `017113-E9FBF5-49BBC9`, billing enabled |
| Apple Firebase app | `1:280562253820:ios:eed3a08d4e7e6a6b677c79`; bundle `com.matteozajac.bedtimestories`; team `4TCJLR98Y5`; App Store ID `6818278413` |
| Authentication | Apple enabled as the sole sign-in provider; native Apple configuration |
| App Check | App Attest registered, one-hour TTL; Firestore and Storage show **Enforced** |
| Firestore | `(default)`, Native, `europe-west1`, deletion protection enabled |
| Voice vault | `gen-lang-client-0154884984-voices`, `EUROPE-WEST1`, uniform access, public access prevention enforced |
| Output bucket | `gen-lang-client-0154884984-audio`, same private settings; Firebase-linked `cloud-audio` rules target |
| Encryption | KMS `europe-west1/bedtime-voices/enrollment-envelopes`, 90-day rotation |
| Queue | `bedtime-voice-worker`, 1 dispatch/sec, 2 concurrent, 30 attempts |
| Worker | Private `bedtime-voice-worker`, revision `bedtime-voice-worker-00002-qpp`, 100% traffic, concurrency 1, timeout 1800s, 2 GiB, maximum 2 instances, scales to zero, request-based CPU allocation |
| Worker identity | `voice-worker@gen-lang-client-0154884984.iam.gserviceaccount.com` |
| Callable identity | `voice-api@gen-lang-client-0154884984.iam.gserviceaccount.com` |
| Functions | All nine Gen 2 Node 22 functions read back **ACTIVE** in `europe-west1`, with the intended runtime identity and worker URL |
| Maintenance | Daily OIDC worker cleanup and five-minute OIDC dispatch recovery enabled |
| Function images | `gcf-artifacts` cleanup policy retains images for seven days |

Worker build `7b356181-da54-4e94-9529-9358dba05031` completed **SUCCESS**. The deployed image is `europe-west1-docker.pkg.dev/gen-lang-client-0154884984/bedtime-voice/worker@sha256:ef43f9b7a8531f4ff7e3e6a90b7bac266d7e3aca44644f6e05ecd1eb28b61530`.

Worker URL: `https://bedtime-voice-worker-czklb4edsa-ew.a.run.app`. Its service-level invoker binding contains only the queue and scheduler service accounts, with no `allUsers` or `allAuthenticatedUsers`. An unauthenticated `/health` request returned **403**. An unauthenticated `startNarration` callable returned **401 UNAUTHENTICATED**.

The worker's actual runtime identity reached the global Google Voices API with **HTTP 200** through a temporary Cloud Run probe job. The probe job was deleted afterward. This verifies API access and voice-list capability; it does not verify human voice creation, model generation, likeness, emotions, or provider deletion. Scheduled worker cleanup and scheduled dispatch recovery both returned **HTTP 200** using their intended OIDC identities.

## Privacy verification

The deployed Firestore and exact custom-bucket rules were retrieved and matched byte-for-byte against source:

- Firestore release `cloud.firestore`, ruleset `de9d96c9-d343-4d90-b5fa-70924381c1d9`, SHA256 `58c755c1c83a5fe6a6bf542bd95ab8ef44caa0c6ec397f2b83b596ea4d5d8bf7`.
- Storage release `firebase.storage/gen-lang-client-0154884984-audio`, ruleset `dbd61247-50e0-4560-a54f-d19776f0b4b3`, SHA256 `e49c605b3ca4b3a1a02f634dfb64354fd2681a122369aad8f617b4e28bd5f3c2`.

Storage's Google-managed service agent has the documented `roles/firebaserules.firestoreServiceAgent` read-only permission required to evaluate account/job document checks. Application users do not receive this role. The API can encrypt retained recordings but cannot decrypt them or read generated audio. The worker has access only to the intended buckets/key and relevant project roles.

Verification passed: six Functions unit tests, six infrastructure helper tests, twelve isolated Firebase emulator tests, Terraform formatting/schema validation, and a final infrastructure plan. Emulator checks cover owner success, cross-user read/list/write denial, private enrollment denial, output expiry, revoked accounts, input owner spoofing, idempotency, and dispatch/deletion recovery. Emulator results and matching deployed source are not a substitute for a live two-account Apple/App Attest exercise.

## Activation status

Deployment is complete; customer narration remains gated off. All deployed Functions have `ENABLE_CLOUD_NARRATION=false`, and the latest documented Internal TestFlight build 9 still has `CloudNarrationEnabled=false` with no bundled Firebase configuration. No new client binary was published for this backend-only deployment.

Before enabling customer access, complete Apple's OAuth code-flow credentials for token revocation, test genuine Apple sign-in/App Attest and account switching on a physical device, and run create/get/style generation/delete with a real consenting adult's reference/consent recordings and fixed `gemini-3.8-flash-tts`. Also verify live A/B isolation and listen to likeness/emotion results. No substitute model or fabricated consent recording was used.

The verified client configuration, deployed variable file, Terraform state/plans and detailed readbacks are stored outside Git under `/Users/mateusz/Library/Application Support/BedtimeStoriesCloud`, with private permissions on a FileVault-enabled Mac. The client configuration has not yet been added to the app bundle. No administrative secrets, OAuth tokens, service-account private keys, or Apple private key were written to the repository or this receipt.

[Open Firebase](https://console.firebase.google.com/u/0/project/gen-lang-client-0154884984/overview). [Deployment procedure](../backend/infra/DEPLOYMENT.md). [Official cross-service rules permission](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service).
