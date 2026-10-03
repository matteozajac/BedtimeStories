# Bedtime Stories cloud voice API

Node.js 22, TypeScript, Firebase 2nd generation callables in `europe-west1`. The API accepts only Firebase ID tokens signed in through `apple.com`, checks revocation/disabled users, requires production App Check, and consumes limited-use App Check tokens on every callable. Voice/account deletion also requires `auth_time` within five minutes. The backend derives the owner UID from the verified token; callers cannot provide UID, provider voice ID, object path, or cloud credentials.

The feature switch defaults to **off**. A configured deployment does not establish that Gemini replication, App Attest, physical recording, Apple token revocation, or deletion passed their live gates.

## Client contract

All functions require a signed-in Apple user and `HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)`.

| Callable | Input | Response |
| --- | --- | --- |
| `beginVoiceEnrollment` | `displayName`, `language: en-US/pl-PL`, `consentVersion: 2026-10-01`, `retentionAccepted: true` | `enrollmentId`, `expiresAt` Unix seconds, provider-verbatim `consentStatement` |
| `uploadEnrollmentRecording` | `enrollmentId`, `kind: reference/consent`, `audioBase64` | `{}` |
| `completeVoiceEnrollment` | `enrollmentId` | `profileId` |
| `approveVoice` | `profileId` after listening to a preview | `{}` |
| `startNarration` | UUID `requestId`, `voiceProfileId`, `draftId`, hex SHA-256 `snapshotHash`, `language`, `preview`, `chapters: [{id,title,paragraphs:[{text,style}]}]` | `jobId` |
| `cancelNarration` | `jobId` | `{}` |
| `deleteVoice` | `profileId` | `{}` |
| `deleteAccount` | `{}` | `{}` |

Reference WAV: 10–30 seconds. Consent WAV: complete provider statement, 2–30 seconds. Both: RIFF/WAVE PCM16, mono, 24 kHz; at most 2 MiB. Recording uploads are immutable and idempotent when identical; start a new enrollment to replace an uploaded sample. The enrollment window is one hour. Completed profiles retain encrypted source/consent recordings until deletion so expired remote voices can be renewed. No raw audio enters client-readable metadata or logs.

Public owner-only metadata is under `users/{uid}/voices/{profileId}` and `users/{uid}/jobs/{jobId}`. Timestamps in Firestore are native `Timestamp`s. Profiles progress through `processing → awaitingApproval → ready`, or `failed/deleting/deleted`. Previews accept `awaitingApproval`; full books require `ready`. Jobs use `queued/processing/ready/failed/cancelled` and contain frozen `draftId`/`snapshotHash`, progress, expiry, and outputs `{chapterId,path,sha256,bytes,duration}`. Download the owner-authenticated object to a local protected file through the Storage SDK; never request a Firebase download URL.

Private accounts, enrollment metadata, immutable manuscripts and encrypted provider mappings are under `privateAccounts/{uid}`. A deleting/deleted root tombstone closes API/rule access and fences stale workers. Ciphertext objects live in the private `VOICE_BUCKET` at `enrollments/{uid}/{profileId}/{reference|consent}.json`; the AES-256-GCM envelope and canonical AAD are defined in `src/encryption.ts` and match the private Python worker. Each object has a random data key wrapped by Cloud KMS. No object has a public download token.

Default limits: 3 active voice profiles, 5 enrollment attempts/day, 20 previews/day, 5 books/day, **one active full-book job per UID**, 1,500 preview characters, and full books limited to 50,000 characters/5,400 words. Final duration is additionally bounded by the worker. Outputs expire after 30 days; an authenticated worker cleanup removes expired cloud artifacts. Existing downloaded/imported local books remain governed by the app library.

## Runtime configuration and permissions

Set only safe resource identifiers in deployment environment; no Gemini key or service-account key file is required:

| Environment | Meaning |
| --- | --- |
| `API_SERVICE_ACCOUNT` | Dedicated callable runtime service account |
| `VOICE_BUCKET` | Backend-only encrypted recording/chunk bucket |
| `OUTPUT_BUCKET` | Firebase Storage bucket with owner-only output rules |
| `KMS_KEY_NAME` | Full Cloud KMS CryptoKey resource name |
| `WORKER_URL` | Private Cloud Run worker base HTTPS URL |
| `TASK_LOCATION` | Queue region; default `europe-west1` |
| `TASK_QUEUE` | Queue ID; default `bedtime-voice-worker` |
| `TASK_SERVICE_ACCOUNT` | OIDC identity with Cloud Run invoker permission on the worker |
| `ENABLE_CLOUD_NARRATION` | Exact `true` enables new enrollment/uploads/narration; absent/false rejects them |

Project identity comes from the managed `GCLOUD_PROJECT`, with `GCP_PROJECT`/`PROJECT_ID` fallbacks for local tests. Give API runtime narrowly scoped Firestore access, voice-bucket object create/get/delete (for immutable-upload recovery), KMS encrypt, Firebase Auth user/token-verification permissions, Cloud Tasks enqueuer, service-account user for the task identity, and Firebase App Check Token Verifier. The worker receives its own Gemini/IAM/KMS decrypt rights; the API never decrypts recordings or provider identities.

Cloud Tasks sends `{kind: enroll/narrate/deleteVoice/deleteAccount, uid, id}` to the private worker's `/tasks` path using OIDC with the base worker URL as audience. Create the queue with bounded retries/backoff and concurrency; use 30 attempts, 30–300 seconds retry backoff, two concurrent dispatches and one dispatch/second as the initial configuration, and worker instance concurrency one. Tasks have a 30-minute dispatch deadline to accommodate bounded work plus an in-flight provider request; the worker checkpoints/yields long work. A Firestore outbox survives enqueue failure; `retryPendingDispatches` repairs pending dispatch every five minutes, including when the feature is disabled. Configure a separate IAM-authenticated Scheduler request to the worker `/cleanup` endpoint.

Scheduled cleanup also retries pending account/voice deletion after queue attempts are exhausted. It isolates failures, preserves deletion intent, and advances a server-only cursor before each bounded attempt so an unavailable provider does not repeatedly starve later accounts. Cleanup never creates or renews a provider voice. It waits for live upload reservations, removes expired/orphan recordings, and repeatedly sweeps deleted-account prefixes to erase late writes from interrupted requests.

Use the user-approved shared project `gen-lang-client-0154884984` (**Always Near Stories**) for TestFlight and production. `.firebaserc` now pins that exact project and the `cloud-audio` Storage target. European infrastructure, runtime identities, billing, and App Attest registration have been provisioned; see the [deployment receipt](../../docs/CLOUD_NARRATION_DEPLOYMENT.md). Keep the feature gate disabled until real voice, Apple OAuth revocation, and device checks pass.

## Local verification and deployment

```sh
cd backend/functions
npm ci
npm test
cd ../..
npx -y firebase-tools@latest emulators:exec --only firestore,storage --project demo-bedtime-cloud 'npm --prefix backend/functions run test:emulator'
```

Use Node 22 and Java 21 or newer on `PATH`. Emulator tests refuse to run without both emulator hosts and only use `demo-bedtime-cloud`. They test cross-owner access, source isolation, write denial, expiry, immutable/idempotent jobs, approval, deletion tombstones, feature gating and outbox recovery. Unit tests cover Apple/recent auth, exact consent acceptance, hostile WAV payloads, request-owner overrides, input cost limits, and AES-GCM context/tampering.

After the shared project and worker are validated, register the **custom output bucket** and bind its explicit Storage target using the [infrastructure helpers](../infra/README.md). `register_output_bucket.py --register --configure-cli` writes ignored `.env.firebase.PROJECT.json` beside the root `firebase.json`; that config targets rules at `PROJECT-audio` rather than the default Firebase bucket. Generate the safe Functions environment with `prepare_functions_env.py` and deploy explicitly (replace the placeholder with the confirmed project ID):

```sh
npx -y firebase-tools@latest deploy --config .env.firebase.CONFIRMED_BEDTIME_PROJECT.json --project CONFIRMED_BEDTIME_PROJECT --only firestore:rules,firestore:indexes,storage:cloud-audio,functions:cloud-voice
```

Keep `ENABLE_CLOUD_NARRATION=false` through Gemini English/Polish quality, retention/deletion and IAM tests; a physical device must verify Apple sign-in, App Attest, recording, download/import, account switching, cancellation and Apple authorization revocation before enabling customer access. Verify real B-as-A token/object attacks against deployed endpoints, not only emulator rules.
