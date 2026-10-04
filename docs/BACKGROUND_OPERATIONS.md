# Background operations

## Audited flows

| Flow | Work owner and recovery | Result destination |
| --- | --- | --- |
| Gemini story generation | Durable owner-scoped server job; temporary input/result retained for at most 24 hours; accepted requests are idempotent | Saved editable draft, then its published book |
| Family voice upload | Protected staged WAVs and receipt; upload resumes after relaunch/sign-in; training continues in the existing private worker | Your Voices review |
| Cloud narration and voice preview | Idempotent request receipt and durable server job; listeners recover work after navigation/relaunch | The original draft's narration review or Your Voices |
| Generated audio download/attachment | App-owned task; account and snapshot checks; atomic rollback preserves previous narration after cancellation | Working draft |
| Book import, editing preparation, export/share, and iCloud library publication | App-owned library task; progress survives navigation; existing atomic storage and recovery retained | Import review or exact library book |
| Large recording and illustration attachment | Retained editor work with a native continued-processing grant; atomic attachment is not advertised as cancellable | Working draft |
| Local Apple story generation | App-owned task; editable partial results survive failure; foreground-only model availability remains a system requirement | Editable draft |

Microphone recording, Photos permission/picking, Apple sign-in, and user review remain interactive. Background work begins after the user supplies the input and starts processing. Audio playback retains its existing audio background mode.

## User experience

The root owns `OperationCenter`, independent of sheets and navigation destinations. It persists owner-scoped operation receipts, handles relaunch/interruption, separates active and recent work, and retains hidden terminal cloud receipts after history is cleared to prevent replayed results recreating a published/deleted draft. Settings includes **Ongoing Operations** and completion-alert preferences. An unobtrusive active-work chip opens the same list.

Completion uses a dismissible in-app banner on the library and presented app sheets. Tapping a banner, history row, or `bedtimestories://operation/{id}` saves the current editor before navigation and opens the exact book, draft narration review, or voice screen. A cold-launch remote tap waits for matching authentication and, for stories, a saved draft. Publishing rewrites old draft destinations to the resulting book. Strict URLs reject credentials, query parameters, fragments, extra paths, and encoded aliases.

Foreground completion is deduplicated across listener snapshots, push arrivals, and relaunch. Local operations schedule local alerts when the app is inactive; cloud completion comes from the backend. Push payloads use generic English/Polish copy and owner IDs rather than book titles, story text, recording contents, or provider identities. Sign-out ends owned Live Activities; account deletion also removes staged private recordings.

Cloud operations use an ActivityKit widget for Lock Screen and Dynamic Island progress, registered with the backend for remote updates/end events. Token registration retries transient errors and refreshes after device registration/foreground entry. Local work requests `BGContinuedProcessingTask`; an unavailable grant falls back to the ordinary finite iOS background allowance. iOS controls execution time and may pause local work; cloud processing continues on the server. This does not promise unlimited device execution.

## Voice defaults

English and Polish each expose Luna, Milo, and Robin, mapped server-side to Gemini's Sulafat, Achernar, and Umbriel. The first loaded ready family voice is preferred for a fresh selection; saved explicit choices survive metadata loading. If no family voice is ready, a storyteller in the selected language is chosen. Supported story language is inferred only from sufficiently confident text, and remains editable.

## Verification

Native tests cover ownership, persistence, cold notification routing, banner deduplication, draft publication receipts, expiry, cancellation before accepted responses, and generated-audio rollback. Backend emulator/unit tests cover owner isolation, task recovery, quota idempotency, cancellation/deletion fences, token rotation, completion preferences, and ActivityKit ordering. Simulator UI checks exercise English/Polish banners, the active chip, Settings entry, operations history, and exact-book links.

Six real worker-identity Gemini requests verified complete mono 24 kHz, 16-bit PCM audio for all three storytellers in both languages. Human listening, physical APNs delivery, suspended/terminated-app Dynamic Island updates, App Attest, microphone enrollment, and iCloud device behavior still require device acceptance. The APNs credential is configured separately in Firebase by the app owner.

Backend API and deployment details: [BACKGROUND_OPERATIONS_BACKEND.md](BACKGROUND_OPERATIONS_BACKEND.md).
