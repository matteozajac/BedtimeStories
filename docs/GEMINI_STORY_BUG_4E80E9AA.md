# Three-minute Polish Gemini story failure — 4 October 2026

Report `4E80E9AA-2233-4786-BD7A-E290A4D1D8D7` came from Always Near Stories `1.0 (16)`, bundle `com.matteozajac.bedtimestories`, on an iPad running iPadOS 27.2. The written report and screenshot describe Gemini failing to create a three-minute Polish book. Pulse, a screenshot and a diagnostics snapshot were included; audio was excluded and video was unavailable. The original archive, extracted evidence and probe results remain under ignored `.build/bug-reports/4e80e9aa-inspection/`.

## Cause

The app requested three minutes at 120 words per minute, with an accepted range of 288–432 chapter words. The corresponding production operation on `generatestorybook-00004-gup` returned a complete but short first book (253 words), then an unfinished expansion. Authentication and both Vertex requests succeeded. The final `incomplete_story` error reached the app after approximately 33 seconds.

A separate live probe with a fabricated Polish fox-and-hedgehog idea reproduced the failure before the fix: the first book had 287 words; the expansion switched to `MEDIUM` thinking while retaining the same 3,440-token limit. It used 3,302 thinking tokens and returned only 124 response tokens before stopping with `MAX_TOKENS`. Google documents that `maxOutputTokens` includes thinking and response tokens, and reaching it can truncate or empty the result: [Gemini thinking token limits](https://ai.google.dev/gemini-api/docs/generate-content/thinking#token-limits-and-max_output_tokens).

The existing fallback compounded the problem: it only repaired books with a target of at least 1,200 words, and required the final attempt itself to contain a complete book. It could not recover the usable first draft after a truncated retry. The report's original prose was not retained by the backend, so its exact text was not replayed.

## Repair

- Reserve thinking tokens separately from the prose/JSON estimate, allow more tokens for Polish, and keep a 49,152-token ceiling below the model's documented 65,536-token maximum. The three-minute Polish expansion now has a 20,544-token allowance. Thinking levels remain `LOW` initially and `MEDIUM` for expansion.
- Retain the most complete eligible short book in request memory across attempts. After two unsuccessful attempts, allow one repair for any reading length, with the existing deficit limit of 25% of the minimum and at most 1,000 words.
- Aim the added scene within the requested whole-book budget and reject additions outside its bounds. Preserve existing prose and place single-chapter additions before the final paragraph or sentence, keeping the ending last.
- Validate the entire repaired book again, check the account/lease before repair and before returning, and release the lease normally. Refusals and account deletion remain terminal failures.
- Log an allowlisted finish reason and numeric output/thinking token counts, without ideas, prose, reasoning text or credentials.

The two generation calls remain bounded to 155 seconds each and the single repair to 35 seconds. Quotas, concurrency, Apple authentication and App Check requirements retain their existing limits. Larger token allowances can permit more billable generation; generation still has explicit token and time ceilings.

## Verification

- The exact service sequence from the report—253-word Polish book, unfinished expansion—failed before the fix with `internal / incomplete_story`. The same emulator regression now returns a validated 360-word book, charges one quota use and clears the lease.
- The token-budget regression failed before the fix and passes afterward through the real provider request/parsing path with mocked transport.
- TypeScript compilation and all 22 backend unit tests and 20 emulator tests pass. The final suites ran on Node.js 22, matching the deployed runtime, and cover single-chapter ending preservation, addition bounds, safety refusal, invalid repair and deletion during repair.
- The real provider expanded the same first book that previously triggered `MAX_TOKENS` into 352 words, using 4,412 thinking tokens and 1,078 output tokens, with finish reason `STOP`. An independent bounded repair of that first book returned a valid 347-word book. Both had three chapters; the Polish prose and repaired transition were inspected locally.

These are backend source, emulator and direct provider checks. The reporting iPad has not been retested.

## Deployment

The scoped `functions:cloud-voice:generateStoryBook` deployment completed on **4 October 2026 at 16:59:16 UTC** in the existing project `gen-lang-client-0154884984`, region `europe-west1`. Live readback confirmed **ACTIVE** revision `generatestorybook-00005-rux`, ready with **100% traffic** and `ENABLE_STORY_GENERATION=true`. The service account, 360-second timeout, four-instance maximum and concurrency of four were preserved. The other nine Functions retained their previous revision/update state.

The exact uploaded source generation `1791133112269583` was downloaded through authenticated tooling. Its `src/story.ts`, compiled `lib/story.js` and `lib/index.js`, package manifest and lockfile matched the validated local files byte for byte. All 14 captured backend input fingerprints remained unchanged through deployment. The deployed handler source retains App Check enforcement and token consumption. A live unauthenticated callable POST returned **HTTP 401 / UNAUTHENTICATED**.

The Firebase MCP deployment job initially reported success without a changed revision; live readback caught that discrepancy. The scoped Firebase CLI deployment performed the verified update. Raw readbacks, source archive and the deployment receipt remain in the ignored inspection directory.

Existing build 16 can use the deployed server repair; no new client build is required.
