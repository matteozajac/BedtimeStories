# Private Gemini voice worker

The Python Cloud Run worker accepts only `{kind, uid, id}` task references. Recordings, provider identifiers, and manuscript snapshots are resolved from private Firestore and Storage using Application Default Credentials. The fixed narration model is `gemini-3.8-flash-tts`; there is no model substitution or API-key authentication.

## Build and deployment contract

Build from `backend/worker` using its Dockerfile. Deploy in `europe-west1`, with **authentication required**, a dedicated runtime service account, concurrency 1, request timeout 1800 seconds, and no `allUsers` or `allAuthenticatedUsers` invoker grants. Grant `roles/run.invoker` only to the queue dispatcher and cleanup scheduler service accounts. Never deploy this application as a public HTTP API. Cloud Run IAM is the request authentication boundary.

Required environment:

| Variable | Value |
| --- | --- |
| `GCLOUD_PROJECT` | Exact BedtimeStories environment project |
| `VOICE_BUCKET` | Private reference/consent/checkpoint bucket |
| `OUTPUT_BUCKET` | Private authenticated Firebase audio bucket |
| `KMS_KEY_NAME` | `projects/.../locations/europe-west1/keyRings/.../cryptoKeys/...` |

The runtime account needs Firestore document read/write, object read/write/delete on these two buckets, KMS encrypt/decrypt on this key, Gemini Enterprise invocation/voice management, and Firebase Auth user revoke/delete. The dispatcher needs permission to create Cloud Tasks and act as its dedicated queue invoker. Use attached service accounts; never export private keys. Keep provider request/response logging disabled. IAM, billing, APIs, App Check, and Apple Auth configuration are provisioned separately from this container.

Cloud Tasks invokes `POST <service-url>/tasks` with an OIDC token whose audience is `<service-url>`, a dispatch deadline of 1800 seconds, bounded rate, and at least 30 attempts with exponential backoff. The scheduler invokes `POST <service-url>/cleanup` daily using its own OIDC token and the same audience. `/health` returns only a fixed liveness response and remains behind IAM.

## Owner and encryption contract

Public `users/{uid}/voices/{id}` and `users/{uid}/jobs/{id}` documents include an immutable `uid`. The corresponding `privateAccounts/{uid}/voices/{id}` and `.../jobs/{id}` include `uid` plus `voiceId` or `jobId`. `privateAccounts/{uid}.state` is `active`, `deleting`, or `deleted`. Deleted account tombstones remain permanently; late tasks cannot recreate private data.

Enrollment objects use `enrollments/{uid}/{voiceId}/{reference|consent}.json` in `VOICE_BUCKET`. Their AES-256-GCM envelope contains `version`, `uid`, `voiceId`, `kind`, `kmsKeyName`, `wrappedKey`, `iv`, and `ciphertext` (ciphertext followed by the 16-byte authentication tag). Each value is base64 where applicable. The AAD is UTF-8 JSON in this exact property order without whitespace: `{"version":1,"uid":"…","voiceId":"…","kind":"reference"}`. A random data key is wrapped by Cloud KMS. Every decrypt verifies the expected owner, voice, kind, version, and configured KMS key before unwrapping. `providerVoice` uses the same envelope with `kind: "providerVoice"` and stores only the provider ID as plaintext inside encryption.

Voice replication posts reference and recorded consent WAVs to the **global `v1beta1` Voices API** with `store:true`, `VOICE_TYPE_REPLICATED`, and no `voice.model`. Creation uses an opaque random display marker, never a parent name or Firebase UID. Stored provider IDs remain backend-only. A newly cloned profile becomes `awaitingApproval`; preview jobs may use it, and `approveVoice` activates it for complete books. Missing/expired provider voices are recreated only from the retained sources while consent remains enabled. Existing approval remains valid for that consented voice renewal.

Generation posts verbatim supplied text to the **global `v1` generateContent API**, with emotion/pacing in `speechMetadata.style`. Sentence/whitespace chunks preserve the exact text and are capped at 200 words/2,400 characters. WAV validation requires 24 kHz mono PCM16 and rejects truncation, partial candidates, or unexpected output formats. The worker strips RIFF headers before joining frames and encodes AAC M4A with ffmpeg. Publication exposes `{chapterId,path,sha256,bytes,duration}` and only happens after fenced ownership/cancellation checks. No Firebase download token, public grant, or signed playback URL is generated.

Job deliveries checkpoint generated chunks in the backend-only bucket and resume after retries. A fenced Firestore lease prevents duplicate workers. Every provider call and publication rechecks account/voice state. Uncertain voice creation is reconciled by its marker and is **never retried blindly**; an unresolved create stays private with `voice_creation_unconfirmed` for operational review. Deletion similarly fails closed with `voice_deletion_unconfirmed` until reconciliation succeeds. The error codes are safe to log; provider payloads, recordings, story text, and tokens are not logged.

## Deletion and retention

Voice deletion first fences new usage, waits for running jobs/enrollment leases, deletes the provider voice and retained source recordings, cancels unfinished jobs, and clears their outputs/snapshots/chunks. Previously completed books remain the user's ordinary audio files. Account deletion removes all provider voices and all account-owned cloud objects/documents, revokes Firebase refresh tokens, deletes the Firebase Auth user, and retains only the account tombstone.

Daily cleanup removes expired 30-day outputs, manuscript snapshots, and checkpoint chunks, and marks public jobs `failed` with `output_expired`. It removes expired enrollment sessions and recordings from sessions that were never submitted; submitted voices retain their encrypted sources via the private profile. Storage rules must deny reads immediately after `expiresAt` even before the scheduled deletion runs. An authenticated scheduler invocation must be provisioned before enabling cloud narration.

Cleanup also retries pending voice/account deletion independently of the finite queue retry budget, with safe per-item failures and a backend-only cursor advanced before provider work. It attempts at most 20 pending deletions and starts no additional attempt after 600 seconds; a single in-flight provider operation may take longer. These paths only delete/reconcile existing voices. Deleted-account tombstones are swept repeatedly for late objects or interrupted metadata cleanup. Active upload reservations postpone deletion; orphan enrollment prefixes are subsequently removed. Expiry/cancellation metadata writes use transaction fences and cannot recreate erased account data.

## Verification

Run offline tests with `python3 -m unittest discover -s backend/worker/tests -v`. They cover tenant rejection before provider calls, authenticated envelope binding, cancellation/deletion races, uncertain-create reconciliation, lease fencing, checkpoint resumption, approval gating, provider renewal, partial-output rejection, and decoded-frame audio joining. ffmpeg/ffprobe are required for encoding tests; the container includes them.

For the live staging feasibility gate, use `backend/scripts/voice_feasibility.py` with human-provided adult reference/consent recordings, a short supplied text file, a private output directory, the staging project, and `--speaker-consent-confirmed`. Optional `--impersonate-service-account` tests the actual runtime identity without downloading a private key. The probe creates, reads, generates two delivery styles, and deletes/verifies deletion of a temporary provider voice. Its report excludes recordings, story text, provider IDs, and OAuth credentials. Successful calls still require human listening review for likeness and emotional quality. Do not synthesize or invent a parent's consent recording.

Verified API references, 2026-10-02: [voice replication and consent](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/text-to-speech/voice-replication), [stored voice management](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/text-to-speech/voice-design), [speech formats and style metadata](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/text-to-speech/overview), [Gemini 3.8 model](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-flash-tts).
