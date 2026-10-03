# Shared cloud deployment — 2026-10-03

## Logging deployment — 3 October 2026

The logging update is deployed to the existing shared project. Cloud Build
`e6b012e5-5b37-44ff-bded-6418fc7ef799` completed successfully. Worker revision
`bedtime-voice-worker-00003-gcr` serves 100% of traffic using image
`europe-west1-docker.pkg.dev/gen-lang-client-0154884984/bedtime-voice/worker@sha256:f1058c75a6ff0ea43e66daeb617e6112510911238d809545b7680f6c5395d2a2`.
The protected Terraform variable file was updated to this same digest.

All nine Functions were rebuilt and redeployed; fresh readback verifies ACTIVE
revision 00003, the existing API service account and `ENABLE_CLOUD_NARRATION=true`.
Worker runtime configuration and private invoker bindings were preserved.
Unauthenticated health access returns 403; authenticated health returns 200.
A malformed task was rejected before any provider or storage work. Cloud Logging
contains its structured ERROR entry, operation ID, original `SafeError` code and
exception frames in `server.py` and `core.py`. This verifies deployed error and
stack logging; it does not establish real voice enrollment or device acceptance.
The existing dispatch-recovery scheduler also completed successfully on its new
Functions revision, with DEBUG Firestore connection start/completion events and
an INFO operation-completed event freshly read back from Cloud Logging.

Deployment, runtime and logging readbacks are retained in ignored
`.build/pti/1.0-11/`. See [logging diagnostics](LOGGING.md).

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

The initial deployment kept all server/client gates off. Following the user's explicit Internal enablement instruction, Apple code-flow credentials were configured, all nine Functions were redeployed with `ENABLE_CLOUD_NARRATION=true`, and Internal **1.0 (10)** was published with its matching client gate and Firebase configuration. Other app configurations retain their disabled client gate. See [enablement and exact release readbacks](CLOUD_NARRATION_INTERNAL_ENABLEMENT.md).

Fresh Functions readback confirms **ACTIVE**, intended `voice-api` identity and enabled narration for all nine functions. Revision IDs are `cancelnarration-00002-wib`, `uploadenrollmentrecording-00002-jib`, `approvevoice-00002-yuj`, `deletevoice-00002-dag`, `startnarration-00002-bom`, `deleteaccount-00002-tuc`, `beginvoiceenrollment-00002-kog`, `completevoiceenrollment-00002-lin` and `retrypendingdispatches-00002-huw`. Post-activation unauthenticated worker/narration probes returned **403/401**.

The actual worker identity successfully generated prebuilt-voice audio with fixed `gemini-3.8-flash-tts`. Real parent voice creation/reuse/deletion, physical Apple sign-in/App Attest and live two-account isolation remain beta acceptance checks. Neither model access nor emulator results establish those outcomes.

Client configuration, deployed variables, Terraform state/plans and detailed provider readbacks are protected outside Git under `/Users/mateusz/Library/Application Support/BedtimeStoriesCloud`. The client configuration is also bundled from an ignored file for Internal build 10. The Apple private key is stored in macOS Keychain and Firebase's managed provider configuration; its plaintext download was removed. No administrative secrets, OAuth tokens, service-account private keys or Apple private key were written to the repository or this receipt.

[Open Firebase](https://console.firebase.google.com/u/0/project/gen-lang-client-0154884984/overview). [Deployment procedure](../backend/infra/DEPLOYMENT.md). [Official cross-service rules permission](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service).
