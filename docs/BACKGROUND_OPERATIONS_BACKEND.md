# Durable cloud operations

Audited on 2026-10-04. Cloud narration and voice enrollment already commit owner-scoped jobs to Firestore before Cloud Tasks dispatches the private Python worker. Their provider processing continues when the app leaves its screen, becomes suspended, or is terminated. Story generation previously performed its entire Gemini request inside `generateStoryBook`; a disconnect could lose the result. New clients now accept an asynchronous story job and observe its result independently of the creator screen.

## API and state contract

- `startStoryGeneration`: existing story parameters and consent plus a client-generated `requestId`. Returns `jobId`, equal to `requestId`. The same ID and parameters return the same accepted operation without consuming another daily quota; changing parameters for an existing ID is rejected.
- `cancelStoryGeneration({jobId})`: cancels the owner job and fences a late provider result. Cancellation prevents attachment, while a provider request already in flight may finish on the server.
- `users/{uid}/storyJobs/{jobId}`: client-readable owner metadata with `id`, `uid`, `state` (`queued`, `processing`, `ready`, `failed`, `cancelled`), `progress`, `language`, `wordsPerMinute`, `createdAt`, `expiresAt`, and `completedAt`. Only a ready job has `result` containing the complete validated book. A failed job has a bounded `errorCode` and optional known `reason`; raw provider messages, request payloads, and credentials never reach this document.
- `privateAccounts/{uid}/storyJobs/{jobId}`: server-only input, payload hash, dispatch outbox, execution lease, and attempts. Accepted input is removed on completion, cancellation, or timeout. Temporary results are removed after 24 hours by the five-minute repair/cleanup schedule; saved books remain in the app's local/iCloud library.

Narration retains its existing idempotent API: `startNarration({requestId, voiceProfileId, draftId, snapshotHash, language, preview, chapters})` returns `jobId`, which is the lowercase validated request UUID. Clients persist this UUID and replay the identical payload after an interrupted acceptance response. A voice preview uses the same callable with `preview: true`; its draft/chapter IDs must also remain stable across replay. Accepted requests remain recoverable after cancellation or voice removal without consuming another quota, while new requests still require current voice ownership and approval. Public narration jobs expose the logical `voiceProfileId` so the app can find/reuse a voice's preview; provider identifiers remain private.

`processStoryGeneration` is a private Firebase task queue function. Acceptance reserves the same daily story quota and single-account generation lease used by the old synchronous API. Dispatch uses a deterministic hashed task ID. Queue failures leave a durable outbox. Transient provider failures receive up to three inference attempts without charging quota again. A seven-minute worker execution lease, 30-minute operation deadline, account tombstone, and execution ID fence prevent stale workers from recreating deleted data or overwriting a replacement result. Existing story-length validation, bounded expansion, and near-complete-scene repair are retained.

Each private story job carries its own `deadlineAt`, so accepting a replacement after the old account lease expires cannot hide the predecessor from cleanup. Voice uploads are also resumable after a lost enrollment-completion response: an active owner may replay already submitted samples only when their hashes match the immutable recordings and the corresponding owner profile still exists.

## Completion alerts and Live Activities

- `registerOperationDevice({deviceId, deviceToken, locale, alertsEnabled})` stores a stable installation ID, FCM token, language (`en` or `pl`), and alert preference in server-only `notificationDevices`. Registering the same FCM token under another signed-in account removes its previous account registration. Tokens expire after 35 days without refresh.
- `unregisterOperationDevice({deviceId})` removes that owner's installation and nested activity/delivery records. This remains available while account deletion is in progress. The app unregisters before signing out; every delivery also checks the account tombstone.
- `registerOperationActivity({deviceId, kind, operationId, activityToken})` accepts only an existing owner operation and registered device. `kind` is `narration`, `voiceEnrollment`, or `storyGeneration`. The ActivityKit push token expires server-side after eight hours and is removed after an end event. Once its token and pending-delivery record commit, registration succeeds independently of provider delivery. It attempts the current state immediately, closing the race where the operation finished before its token arrived; failed delivery remains pending for the five-minute repair schedule (at most 100 pending records per run). Expiry ends retries without removing a valid FCM device registration.

Firestore triggers observe public narration jobs, voice profiles, and story jobs. Voice `awaitingApproval` counts as ready for completion; later approval does not send another alert. Preview narration does not produce a completion alert. Cancellation quietly ends a registered Live Activity. Completion alerts honor `alertsEnabled`, while Live Activity progress remains available when alerts are disabled.

The push contains generic English or Polish copy and `ownerID`, `operationId`, `kind`, `state`, `eventId`, and `deepLink` (`bedtimestories://operation/{id}`). It contains no book title, story idea, chapter prose, recording contents, provider voice ID, or arbitrary error detail. The app must check `ownerID` against its current cloud account, deduplicate `eventId`, and resolve the operation into its own local book or voice screen. Missing operations fall back to the operations list.

ActivityKit content-state is exactly `{operationID, title, subtitle, progress, state}`. States are `queued`, `running`, `ready`, `failed`, and `cancelled`; title/subtitle are generic localized progress copy. FCM uses `apns.liveActivityToken`, APNs `event: update/end`, and a two-minute dismissal delay for terminal states. Per-activity delivery claims and version cursors serialize progress. APNs timestamps strictly increase by Unix seconds; if two versions arrive in one second, the sender waits at most one second so it never emits an equal or future timestamp. Older out-of-order Firestore versions cannot rewind progress. Per-device delivery receipts and APNs collapse IDs deduplicate completion alerts; an interrupted send remains at-least-once, so client event-ID deduplication is still required. Receipt and activity writes are fenced against account/device deletion, and an invalid older FCM token cannot erase a newly rotated registration.

## Deployment and validation

Deploy Functions, Firestore rules, and indexes in the existing dedicated project:

```sh
npx -y firebase-tools@latest deploy --project gen-lang-client-0154884984 --only functions:cloud-voice,firestore
```

New function exports: `startStoryGeneration`, `cancelStoryGeneration`, `processStoryGeneration`, `registerOperationDevice`, `unregisterOperationDevice`, `registerOperationActivity`, `narrationOperationChanged`, `voiceOperationChanged`, and `storyOperationChanged`. Existing `generateStoryBook` remains available to older builds and `retryPendingDispatches` also repairs/purges story and notification records.

Firebase creates the `processStoryGeneration` Cloud Tasks queue in `europe-west1`. Its dispatch limit is four concurrent requests, one per second, with eight infrastructure delivery attempts and 60–300-second backoff. The API runtime is `voice-api@gen-lang-client-0154884984.iam.gserviceaccount.com`, and the Admin SDK also uses this identity in the task OIDC token. Verify:

- The API service account can enqueue into the new queue (`roles/cloudtasks.enqueuer`).
- The private task function/Cloud Run service allows only the API service account to invoke it. Its source declares this invoker explicitly.
- Each completion-trigger service allows its configured Eventarc identity (the API service account) to invoke it through a service-scoped `roles/run.invoker` member. An active trigger deployment alone does not prove this grant exists.
- The enqueuer can act as the API service account (`roles/iam.serviceAccountUser` on itself); the Cloud Tasks service agent can mint its OIDC token if the project's existing Cloud Tasks service-agent role does not already provide it.
- The FCM API (`fcm.googleapis.com`) is enabled and the API service account has `cloudmessaging.messages.create` (for example `roles/firebasecloudmessaging.admin`).
- The target Firebase Apple app has a valid APNs credential for `com.matteozajac.bedtimestories`. An FCM token alone does not establish APNs provisioning or successful physical-device delivery.
- Firestore collection-group indexes from `backend/firestore.indexes.json` have completed creation before reading pending jobs, notification token ownership, and cleanup records.

Validation passed 29 unit tests and 42 Firestore/Storage emulator tests, including the pre-existing story repair and built-in voice catalog suites. Mocked provider/messaging checks cover quota idempotency, dropped dispatch, worker recovery, cancellation, account deletion, stale execution fencing, expired predecessor cleanup, lost enrollment-completion replay, owner-only rules, concurrent device ownership transfer, FCM token rotation, notification retry/deduplication, disabled alerts, preview suppression/recovery, ActivityKit payload/timestamp compatibility, APNs credential failure acceptance/recovery, and bounded activity retry expiry. Initial logs are in `.build/background-operations-unit.log` and `.build/background-operations-emulator.log`; the final registration-fix runs are in `.build/pti/1.0-17/activity-registration-diagnosis`. Real APNs delivery, Dynamic Island updates while the app is suspended, App Attest, voice enrollment, and production Gemini narration require physical-device verification.

Official references: [Firebase task queue functions](https://firebase.google.com/docs/functions/task-functions), [FCM Live Activities](https://firebase.google.com/docs/cloud-messaging/customize-messages/live-activity), [Admin SDK APNs config](https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.apnsconfig).

## Real built-in voice probe

On 2026-10-04, six short generic story sentences successfully synthesized using `gemini-3.8-flash-tts` through an impersonated `voice-worker` runtime identity. Each output passed the worker's complete PCM WAV validation: one channel, 24 kHz, 16-bit samples. This confirms the actual provider accepts all three catalog timbres for both language requests; language/pronunciation quality still requires listening review.

| Logical profile | Provider timbre | Language | Validated duration |
| --- | --- | --- | --- |
| `builtin-en-luna` | Sulafat | English | 7.92 s |
| `builtin-en-milo` | Achernar | English | 7.88 s |
| `builtin-en-robin` | Umbriel | English | 8.36 s |
| `builtin-pl-luna` | Sulafat | Polish | 9.60 s |
| `builtin-pl-milo` | Achernar | Polish | 7.80 s |
| `builtin-pl-robin` | Umbriel | Polish | 8.84 s |

Disposable audio and safe reports are in the private `.build/pti/1.0-17/voice-probe` directory (0700; files 0600). No custom voice was created. The narrowly scoped temporary developer token-creator binding was removed, and a final IAM readback confirmed it absent. The protected variable file and Terraform state reference worker image `sha256:5b3965334a9b85bb2bead6b5cd6fe476963c5fd9359052e4248303828615484e`, matching deployed revision `bedtime-voice-worker-00004-ww6`.

## Infrastructure state reconciliation

On 2026-10-04, the existing FCM API, completion-notification custom role/member, API Eventarc receiver member, story task identity/OIDC members, and story queue enqueuer member were imported into the protected local Terraform state. The unavailable `firebasecloudmessaging.googleapis.com` API name was removed from the enablement list; the enabled FCM send service is `fcm.googleapis.com`. Cloud Run ignores only descriptive `client`/`client_version` metadata from authorized gcloud deployments, while Terraform continues to manage its image and runtime configuration.

The exact reviewed scoped plan was applied to persist refreshed worker state with **0 resources added, changed, or destroyed**. A subsequent scoped plan returned exit code 0 with no changes; formatting and validation passed. Authenticated readback confirmed the notification role contains only `cloudmessaging.messages.create`, every new IAM member exists, FCM is enabled, and `processStoryGeneration` is running with four concurrent dispatches, one request per second, eight attempts, and 60–300-second backoff. State backups, saved plans, and receipts remain outside Git in the protected state directory (0700 directory; 0600 files).

Final boundary inspection found that the three completion-trigger services were missing invocation permission for their configured API identity. Service-scoped `roles/run.invoker` members were added for that identity on `narrationoperationchanged`, `voiceoperationchanged`, and `storyoperationchanged`, then imported into Terraform. The reviewed follow-up scoped plan reported no changes and applied with zero resource mutations. Readback confirms those services and the story task service require IAM and have only their expected service-level invoker; the voice worker retains its queue/scheduler invokers. No public invoker was added, and the pre-existing project-level compute identity grant was preserved.

One bounded production smoke task used fresh nonexistent owner/job IDs after verifying that the missing-document branch returns before any write or provider call. The Admin Functions SDK enqueued it using an impersonated API identity. Its correlated Cloud Run trace recorded HTTP **204**, a single Firestore read transaction, and `cloud_operation_completed` in **505 ms**. The task disappeared from Cloud Tasks, all four account/job documents remained absent, and the temporary developer impersonation grant was removed with absence verified afterward. Safe receipts are in private `.build/pti/1.0-17/queue-noop-probe`; no user account, custom voice, story content, or provider inference was created by this smoke.

## Physical registration failure diagnosis

A supplied build-17 device log was correlated with seven production registration failures between 18:43:42 and 18:44:12 UTC on 2026-10-04. Authentication and token persistence succeeded, then the initial FCM ActivityKit send failed with `messaging/third-party-auth-error` / `THIRD_PARTY_AUTH_ERROR` / `UNAUTHENTICATED`. Firebase documents this as missing or invalid APNs credentials. Propagating that delivery failure after committing registration incorrectly made the client retry an already accepted token; registration now acknowledges acceptance and retains bounded pending delivery instead. Diagnostics expose only allowlisted messaging codes and existing safe frames, with no provider response or token contents.

The user has explicitly deferred APNs credential provisioning. Actual remote notification and suspended-app Live Activity delivery remain blocked by that configuration; the acceptance fix and mocked recovery tests do not establish production APNs delivery. The redacted server evidence and test/deployment receipts are kept in private `.build/pti/1.0-17/activity-registration-diagnosis`. Reference: [Firebase Cloud Messaging error codes](https://firebase.google.com/docs/cloud-messaging/error-codes).
