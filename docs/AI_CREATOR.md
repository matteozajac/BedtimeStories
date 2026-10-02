# Create a book from an idea

Open **Library → + → Book Creator → Create from an Idea**. Enter a description up to 600 characters, choose English or Polish, the reader’s age, a whole-book reading time (1–30 minutes), and a reading pace (80–180 words/minute). Select a processing mode and tap **Create Story Draft**. The result contains a title, summary, and fully written chapter text; it opens in the existing editor for review, pictures, narration, and **Save**. Text generation does not create pictures or audio.

## Complete-book generation

The app requests the entire book in **one guided response and one session**. The same context holds the description, characters, chapter sequence, and ending. The target is reading minutes × words/minute across all chapter prose. A duration-specific guided schema limits the chapter count to a sensible range (up to 12, with at most two for a two-minute/240-word story). The model chooses within that range and is prompted to keep events chronological, with the resolution only in the final chapter. On-device creation supports up to 600 target words (five minutes at 120 words/minute); longer books require explicitly choosing PCC. Local token counting includes instructions, prompt, schema, a 200-token margin, and the response; a request is rejected before inference if too little response space remains.

`StoryOutputValidator` normalizes whitespace and invisible formatting characters, checks a nonempty title/summary, a permitted chapter count, unique chapter titles and bodies, at least 60 words of story text per chapter, size limits, sentence-ending punctuation, and a whole-book prose count within 80–120% of the requested target. Title, summary, and illustration guide are excluded from duration. Guided structure alone is insufficient: a syntactically valid field can still be empty or truncated.

An invalid or unparseable response causes **one fresh complete-book retry** with the same description and settings plus the measured rejected word count and an explicit expansion/reduction instruction. The retry retains the whole brief and requested structure; it never combines incomplete pieces from different responses. Refusals, quota failures, network errors, and unsupported languages are not retried or routed to another model. Only a complete validated response becomes a new draft, saved atomically once. Repeated invalid output shows recovery guidance and saves no partial book. Previous drafts remain safe. Older partial drafts are still editable.

**Stop Creating**, leaving the screen, or backgrounding cancels generation. If cancellation arrives after persistence, the already complete saved book remains accessible. The description stays in local preferences. Publication to the default library still requires **Save**, and uses the existing `book.json`, Markdown, and `.bedtimestory` format.

## Processing and languages

**On This Device** uses `SystemLanguageModel.default`. It needs eligible hardware, Apple Intelligence enabled, and downloaded assets. **Private Cloud Compute** uses `PrivateCloudComputeLanguageModel` explicitly and sends the brief and entire requested story context to Apple; it requires internet, remaining quota, and an entitled app build. The app never silently switches modes. Default guardrails remain enabled, app instructions are separate from story data, and technical errors/private prompts are not shown in recovery messages.

English and Polish are offered; runtime `supportsLocale` governs availability. This Mac’s local model supports English and does **not** support Polish. Unsupported selections receive an explanation instead of output in another language. PCC language checks run asynchronously. UI text is English/Polish. See [dated primary-source research](FOUNDATION_MODELS_RESEARCH.md).

## Enabling Private Cloud Compute

1. The Account Holder requests the managed entitlement [from Apple](https://developer.apple.com/contact/request/private-cloud-compute/). Check [current eligibility](https://developer.apple.com/private-cloud-compute/).
2. After Apple approves, enable the granted capability for **com.matteozajac.bedtimestories** in Certificates, Identifiers & Profiles and regenerate provisioning profiles. This is a Developer Account capability, rather than an App Store Connect metadata setting. [Apple’s capability request guide](https://developer.apple.com/help/account/capabilities/capability-requests).
3. The app's **Release** configuration now selects `Config/PrivateCloudCompute.entitlements` and `BEDTIME_PRIVATE_CLOUD_COMPUTE` together. Debug stays local-only; `Config/PrivateCloudCompute.xcconfig` remains an explicit override for entitled device testing. Verify the exported signature and embedded profile include Boolean `com.apple.developer.private-cloud-compute`, then distribute a new supported entitled build.

On 2 October 2026, the approved PCC capability was saved and read back as enabled for this App ID in Safari. A new App Store distribution profile, **Always Near Stories PCC App Store 2026-10-02**, grants PCC and the existing iCloud container and reuses the installed Apple Distribution certificate. Profile UUID: `3af35bdd-ce98-4c8a-bd6a-03cf35d8aaa7`; expiration: 5 March 2027. Model `availability` alone does not prove entitlement authorization. A compile-only check cannot prove successful PCC generation. The user reported successful PCC creation with entitled build 6. The new longer-duration flow still needs an eligible physical-device check.

## Illustrations

**Generate Cover Picture** and **Generate Chapter Picture** open the native Image Playground sheet. A short scene is prepared using the on-device Foundation Model when available; the sheet otherwise receives extracted story context. Every image receives the same gentle pastel storybook style and shared character/setting guide. An existing cover is passed as a visual reference for chapter pictures. Only Apple’s illustration style is offered. The person reviews and accepts the image; it becomes part of the local working copy until **Save**. Existing photos can still be replaced or removed. Unsupported devices show an explanation and keep photo import available.

## Build 7 validation — 2 October 2026

- 27 native tests passed in optimized Release on iPhone and Debug on iPad. They cover existing library/player/default storage, full-book generation, measured-length retries, duration-specific schemas, edits with stable IDs/media, discard/recovery, same-size/same-time source conflicts, full-book narration, and reading metadata. Release uses only an invocation-level `ENABLE_TESTABILITY=YES` override.
- 8 Swift core tests and 6 Python authoring tests passed.
- Real on-device-model inference on macOS 27 with production generation/schema/validation sources passed a two-minute target at 120 words/minute: `[134,83]` words, total 217, and a five-minute target: `[126,114,115,100,94]`, total 549. Each final book used one response. Earlier prompt-only trials exceeded duration or returned short chapters; the final duration-specific schema and measured retry address those observed failures. These two smoke tests do not establish reliability across all ideas, languages, devices or durations.
- iPhone UI checks verified published-book editing, appended text saved and reopened under the same identity, Discard retaining the original title, and creation with an added second chapter and **Save** returning to the library. Reopening the new book shows **Close**, the retained chapters, and total words. The Polish iPad screen shows **20 minutes × 120 words/minute = 2400 words** with no chapter-count picker: [reading-time screen](qa/reading-time-ipad-pl.png).
- The simulators report Image Playground unsupported. Sheet/illustration APIs compile, prepared prompts use shared appearance/style and chapter context, but actual image acceptance needs an eligible physical device. Likewise, no physical 20-minute PCC generation or simultaneous two-device iCloud edit was performed in this run.

## Earlier validation — 2 October 2026

- For build 6, **20 native tests passed in Release and 20 in Debug** on the dedicated iPhone simulator. The compilation-gate assertion verifies PCC enabled in Release and blocked in Debug; Release tests used an invocation-only `ENABLE_TESTABILITY=YES` override. The ordinary optimized device archive and Internal-only IPA were signed with PCC and Production iCloud entitlements, and the exact build's Internal TestFlight access was read back. These checks do not establish successful physical-device PCC inference.
- The original empty-response behavior was reproduced with an injected empty chapter: the old implementation failed rather than recovering. The revised test verifies a complete-book retry and exactly one complete saved draft.
- **20 native tests** passed on both iPhone/iPad simulators (the final iPhone run used a fresh dedicated simulator after installation/boot failures in the earlier runner), covering existing library/player/creator behavior, 8 generation checks, and 5 automatic-library/migration checks.
- **8 Swift core tests** and **6 Python authoring tests** passed.
- Real local inference using the same generator/model/persistence sources on macOS 27 produced complete books with 1, 3, 4, and 2 chapters. Word counts were `[99]`, `[126,96,75]`, `[96,89,90,73]`, and `[108,98]`. The four-chapter book needed the validation retry and then passed. Full generated texts were inspected for connected events and a gentle ending; these are smoke tests, not comprehensive editorial evaluation.
- An English iPhone simulator UI run created **Milo and the Star Light** in four chapters of 134, 148, 132, and 106 words. All text fields were inspected; publication produced four nonempty chapter files in the automatic library. The book survived app termination/relaunch and opened in the reader. Screenshots: [complete draft](qa/whole-book-draft-iphone.png), [reader after relaunch](qa/whole-book-reader-iphone.png).
- The Polish iPad UI verified Continue consent, automatic setup, existing-book copy, fixed storage destination, retry action, and family-sharing explanation with no library folder chooser.
- The earlier build 5 was signed with the exact iCloud app container and no PCC entitlement. The subsequent PCC profile grant is verified as described above; signed-build delivery is recorded in [TESTFLIGHT.md](TESTFLIGHT.md). The user subsequently reported successful cloud creation with build 6; this is user-reported hardware evidence.

Reproduce native checks:

```sh
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Physical iPhone/iPad checks remain for speed, story quality across ages/languages, model preparation, offline generation, background cancellation, Dynamic Type, and VoiceOver. Cloud checks require the entitlement grant and include network loss, quota, privacy UI, and successful generation. Simulator inference uses the Mac’s model and cannot establish hardware performance.
