# Diagnosing app and Gemini failures

The app uses the resolved MZAppFoundation 0.5.1 logger and local Pulse store.
Open **Settings → Developer → Open Logs**, or enable Developer Mode and shake
the device. Select a log entry, then tap **Info** to inspect its source and metadata. Keep the
Debug level included in the console filters to see connection traces.
The clipboard button opens Sessions when diagnosing a previous app launch.
Copied plain-text logs now include each entry's context and, for failures, safe
technical explanations, original type/domain/code, nested causes, caller and
capture locations, and the full bounded stack. This is rendered only by the
app-owned local Pulse sink; diagnostic event codes and structured fields remain
unchanged for other destinations.
The app's Pulse sink preserves metadata asynchronously on the store's write
context. This avoids Foundation 0.5.0's synchronous metadata-repair deadlock
when the console is observing saves on the main thread.

## App evidence

`AppLog` and injected `AppLogging` sinks support trace, debug, info, warning,
and error calls. Foundation has no separate trace severity, so trace entries
persist as **Debug** with `verbosity=trace`. They are stored without sampling.
Recoverable retries, cleanup failures, and cached fallbacks are warnings;
failed operations are errors. Expected cancellation is trace or is suppressed.

Errors retain their type, domain, signed code, bounded underlying causes, caller
file/function/line, and stack provenance. Pulse details contain
`error.cause.<index>.*`, `error.stack`, and individual `error.stack.00`,
`error.stack.01`, etc. Individual frames preserve spaces and stay readable.
Swift reporting stacks identify where an error was captured; they do not claim
to identify the original throw. Previously supplied stacks remain supplied.
The app's local adapter renders these details into the text that Pulse's normal
copy/share action exports. Pulse's Info view still retains the structured fields.

File actors capture immutable error snapshots before delivering ordered logs
to the main-actor sink. Firebase and audio delegate callbacks also capture
snapshots before their main-actor hop. Presentation wrappers retain the original
SDK evidence, and a reported-failure marker prevents views from reporting the
same cloud operation again.

Coverage includes story generation and validation attempts, draft saves and
imports, library/iCloud downloads and fallback, audio sessions and decoder
failures, Apple/Firebase sign-in, App Attest provider setup, callable requests,
Firestore listeners/document decoding, cloud output downloads/checksums,
private recovery files, and voice/narration worker state transitions.

Book editing records a single operation ID through checkout, provider downloads,
manifest reading, indexed asset copies, fingerprint validation, draft creation and
publication. iCloud waits report download status changes and a five-second
heartbeat, with asset kind/index, elapsed time and the existing 45-second timeout.
Provider coordination records requested and granted access separately. A failed
phase preserves its original error snapshot before unwinding; cancellations and
edit-conflict recovery keep their existing behavior.

The app audit also added explicit navigation/import/share/offline actions,
editor changes and chapter actions, migrations and progress recovery, model
availability/inference/validation, playback controls/sleep/track preparation,
reader loading, and enrollment/narration UI transitions. Rendering, every
keystroke and every audio buffer do not produce new log entries. Corrupt progress
reads are deduplicated until the stored value changes.

## Following a Gemini request

Gemini runs in the private Python worker. Its exception stack belongs in the
worker logs. The app reports failed worker states once per state transition,
including an allowlisted `backend_error_code`, `failure_evidence=server_state`,
and a `task_key`. That app stack is a reporting stack for the received state.

`task_key` is the same SHA-256 key used for Cloud Tasks naming:
`SHA256(kind + ":" + uid + ":" + itemID)`. Enrollment and profile IDs coincide;
narration uses the returned job ID. The raw account/item identities are excluded
from log fields. Copy `task_key` from Pulse and find matching Functions/worker
events in Cloud Logging. Random diagnostic operation IDs group individual app,
callable, and worker attempts within each process.

Functions record callable/connection start, completion, latency, safe failure
causes, and durable dispatch recovery. The worker records Firestore, Storage,
KMS, Auth, and Gemini connection phases. Gemini evidence includes model,
attempt, HTTP status, allowlisted Google RPC status, elapsed time, retry delay,
and whether a failed create may have committed. Existing retry and ownership
rules are preserved.

Backend error snapshots include bounded cause chains and each cause's frame
filename, function, line, and stack origin. Python preserves exception frames;
Node preserves V8 frames. Neither serializes exception messages, source lines,
locals, arbitrary provider bodies, or full filesystem paths. Intermediate
connection adapters annotate and trace failures; the operation owner records
the error. Retried attempts and separate recovery failures remain observable.

## Privacy and delivery

Messages are fixed technical descriptions. Metadata contains only audited
phases, counts, timings, booleans, technical codes, and correlation keys.
Credentials, tokens, account IDs, story text/titles/prompts, voice names,
recordings, storage paths, URLs, and raw provider error messages are excluded.
SDK-wide HTTP debug logging and request/response body capture are not enabled.
Local Pulse logging remains available with remote Foundation diagnostics off.

Backend changes need deployment to affect production logs. Source/build tests
and intercepted Gemini responses do not establish live Gemini or physical
microphone/playback behavior.

## Verification

`Tests/AppTests/LoggingTests.swift` verifies caller forwarding, readable persisted
Pulse frames, nested/supplied evidence, one-entry error routing, cancellation,
private-data exclusion, file-actor fallback/recovery, and backend correlation.
`Tests/AppTests/DiagnosticTextTests.swift` verifies normal copied text, original
diagnostic payloads, remote opt-out, complete checkout timelines, preserved
failed-phase decoding evidence, Gemini explanations, and repeated errors while
a console fetched-results controller observes saves.
The worker and Functions diagnostics tests exercise private exception text,
bounded/cyclic causes, connection phases, concurrency context isolation, retry
evidence, and safe provider status codes.

Verified on 2026-10-03:

- 55 local simulator app tests and 9 standalone core tests passed.
- The signed Internal build 12 archive/export succeeded with Firebase linked.
- Local binary isolation passed; Ruby setup syntax and generated logger hooks passed.
- Gitleaks found no secrets in the changed source and new diagnostics files.
- A filesystem failure was inspected in Pulse's message text and Info view:
  `LibraryRepository.swift`, `scan(root:discoveredFolders:)`, line 66, Cocoa
  code 260, underlying POSIX code 2, safe explanations and readable individual
  reporting-stack fields. The screenshot is
  `.build/logging-evidence/pulse-context-and-stack-build-12.png`.
- The deadlock regression completed 20 observed error saves; the app remained
  responsive with its actual Pulse console open. The captured pre-fix thread
  sample is `.build/logging-evidence/foundation-pulse-console-deadlock.sample.txt`.

The app-test result bundle is
`.build/mz-local/Logs/Test/Test-BedtimeStoriesLocal-2026.10.03_20-04-48-+0200.xcresult`.

The preceding backend logging release passed 52 worker tests and 10 Functions
tests, with no worker skips. The worker and all nine Functions are deployed
with that implementation; build 12 adds app logging only.
A harmless invalid-task probe verified a structured worker ERROR and original
exception frames in Cloud Logging. The dispatch-recovery scheduler verified
DEBUG Firestore connection timelines and successful completion on the new
Functions revision. See the [deployment receipt](CLOUD_NARRATION_DEPLOYMENT.md)
and [latest Internal build](TESTFLIGHT.md).
