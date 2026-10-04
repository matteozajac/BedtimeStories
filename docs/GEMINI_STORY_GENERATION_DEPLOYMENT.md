# Gemini story generation — 4 October 2026

Gemini book creation is deployed in the existing **Always Near Stories** Firebase project `gen-lang-client-0154884984`. `generateStoryBook` is **ACTIVE**, enabled, and running Node.js 22 in `europe-west1`, with revision `generatestorybook-00005-rux` receiving 100% traffic. The callable uses `voice-api@gen-lang-client-0154884984.iam.gserviceaccount.com`, timeout 360 seconds, maximum four instances and concurrency four. `deleteAccount` is ACTIVE at `deleteaccount-00004-div` and removes story quota/lease metadata before existing account cleanup.

The 4 October 16:59 UTC backend repair reserves thinking-token headroom and recovers complete short books after a truncated expansion. The deployed source archive matches the tested implementation, and the live unauthenticated callable still returns 401. Existing Internal build 16 uses this server change without a new app build. See [the bug analysis and deployment receipt](GEMINI_STORY_BUG_4E80E9AA.md).

The fixed provider is `gemini-3.8-flash` on the global Vertex endpoint. Apple-only authentication verifies revoked/disabled accounts, App Check tokens are required and consumed, and ownership comes from the verified UID. The client cannot submit ownership, credentials, prompts, model IDs or retry context. One active request and ten requests per UTC day are enforced transactionally. Ideas and completed prose stay in request memory; Firestore stores only private quota/lease metadata. No Gemini key is bundled in iOS.

Terraform applied only the custom inference role and API binding: two additions, no existing changes or destruction. The role `projects/gen-lang-client-0154884984/roles/bedtimeStoryGeneration` contains only `aiplatform.endpoints.predict`. A temporary developer impersonation grant used for provider verification was removed; the API service account's final policy contains no token-creator binding. An unauthenticated request to the deployed callable returned **401 / UNAUTHENTICATED** after the final update.

## Validation

- **22 unit tests** passed for bounded input, Polish Unicode counting, spoofed fields, consent, complete prose, safe parsing/refusal, schema, thinking/prose token budgets and ending-preserving scene repair.
- **20 emulator tests** passed, including owner quotas, concurrent requests, lease expiry, provider failure, account deletion during generation/repair, complete-book retry, short-book recovery after truncated expansion, bounded scene repair and refusal to repair substantially incomplete books.
- **59 optimized Internal app tests**, **9 core tests**, **6 Python authoring tests**, and the Local binary SDK-isolation audit passed. The main app's signed device archive compiled the real Firebase implementation.
- Real provider requests using the actual API identity returned valid Polish (one-minute request: 76 words), English (one-minute request: 84 words), and Polish (five-minute request: 586 words) books.
- A maximum 30-minute Polish request at 180 words/minute returned **12 complete chapters / 4,465 words**, within the existing 4,320–6,480 accepted range. Long output initially fell short; the final implementation expands its complete draft and, for a bounded remaining deficit, adds one connecting scene before validating the whole book again. The repaired scene was inspected alongside its next chapter for continuity and natural Polish.

The two full provider calls are each bounded to 155 seconds. A final connecting-scene repair is bounded to 35 seconds and a deficit of at most 25% of the minimum, capped at 1,000 words. The account lease expires after 420 seconds. Cancellation immediately stops the app's wait and discards late output; already-dispatched Google processing may finish. Every returned result passes full server and app validation before draft persistence.

Provider smoke tests and emulator ownership tests do not establish physical Apple sign-in/App Attest, live account switching, iCloud sync, or installation of this build. Those remain device acceptance checks. Main Internal alone enables the app's existing remote configuration. [Creator behavior](AI_CREATOR.md), [Internal release](TESTFLIGHT.md).

Official provider references: [Gemini 3.8 Flash](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-flash), [structured output](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/control-generated-output), [thinking levels](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/thinking), [inference IAM](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/access-control).

Raw receipts and test artifacts remain in ignored `.build/`; Terraform state and account-policy receipts remain in the existing protected local cloud directory. No administrative secrets are committed.
