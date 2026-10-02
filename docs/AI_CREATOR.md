# Create a book from an idea

Open **Library → + → Book Creator → Create from an Idea**. Enter a description up to 600 characters, choose English or Polish, the reader’s age, and 1–4 chapters. Select a processing mode and tap **Create Story Draft**. The result contains a title, summary, and fully written chapter text; it opens in the existing editor for review, pictures, narration, and **Add to Library**. Text generation does not create pictures or audio.

## Complete-book generation

The app requests the entire book in **one guided response and one session**. The same context holds the description, characters, chapter sequence, and ending. Chapters are prompted at 90–140 words to fit the local model’s 4K context. Local token counting includes instructions, prompt, schema, a 200-token margin, and the response; a request is rejected before inference if too little response space remains.

`StoryOutputValidator` normalizes whitespace and invisible formatting characters, checks a nonempty title/summary, exact requested chapter count, unique chapter titles and bodies, at least 60 words of story text per chapter, size limits, and sentence-ending punctuation. Guided structure alone is insufficient: a syntactically valid field can still be empty or truncated.

An invalid or unparseable response causes **one fresh complete-book retry** with the same description and settings. The retry retains the whole brief and requested structure; it never combines incomplete pieces from different responses. Refusals, quota failures, network errors, and unsupported languages are not retried or routed to another model. Only a complete validated response becomes a new draft, saved atomically once. Repeated invalid output shows recovery guidance and saves no partial book. Previous drafts remain safe. Older partial drafts are still editable.

**Stop Creating**, leaving the screen, or backgrounding cancels generation. If cancellation arrives after persistence, the already complete saved book remains accessible. The description stays in local preferences. Publication to the default library still requires **Add to Library**, and uses the existing `book.json`, Markdown, and `.bedtimestory` format.

## Processing and languages

**On This Device** uses `SystemLanguageModel.default`. It needs eligible hardware, Apple Intelligence enabled, and downloaded assets. **Private Cloud Compute** uses `PrivateCloudComputeLanguageModel` explicitly and sends the brief and entire requested story context to Apple; it requires internet, remaining quota, and an entitled app build. The app never silently switches modes. Default guardrails remain enabled, app instructions are separate from story data, and technical errors/private prompts are not shown in recovery messages.

English and Polish are offered; runtime `supportsLocale` governs availability. This Mac’s local model supports English and does **not** support Polish. Unsupported selections receive an explanation instead of output in another language. PCC language checks run asynchronously. UI text is English/Polish. See [dated primary-source research](FOUNDATION_MODELS_RESEARCH.md).

## Enabling Private Cloud Compute

1. The Account Holder requests the managed entitlement [from Apple](https://developer.apple.com/contact/request/private-cloud-compute/). Check [current eligibility](https://developer.apple.com/private-cloud-compute/).
2. After Apple approves, enable the granted capability for **com.matteozajac.bedtimestories** in Certificates, Identifiers & Profiles and regenerate provisioning profiles. This is a Developer Account capability, rather than an App Store Connect metadata setting. [Apple’s capability request guide](https://developer.apple.com/help/account/capabilities/capability-requests).
3. Build with `Config/PrivateCloudCompute.xcconfig`. It selects the merged iCloud/PCC entitlements and `BEDTIME_PRIVATE_CLOUD_COMPUTE` condition together. Verify the exported signature and embedded profile include Boolean `com.apple.developer.private-cloud-compute`, then distribute a new supported entitled build.

The ordinary build keeps PCC unavailable while approval/signing is pending. Model `availability` alone does not prove entitlement authorization. A compile-only check cannot prove successful PCC generation. Eligible-device TestFlight/ad hoc testing is required after the grant.

## Validation — 2 October 2026

- The original empty-response behavior was reproduced with an injected empty chapter: the old implementation failed rather than recovering. The revised test verifies a complete-book retry and exactly one complete saved draft.
- **20 native tests** passed on both iPhone/iPad simulators (the final iPhone run used a fresh dedicated simulator after installation/boot failures in the earlier runner), covering existing library/player/creator behavior, 8 generation checks, and 5 automatic-library/migration checks.
- **8 Swift core tests** and **6 Python authoring tests** passed.
- Real local inference using the same generator/model/persistence sources on macOS 27 produced complete books with 1, 3, 4, and 2 chapters. Word counts were `[99]`, `[126,96,75]`, `[96,89,90,73]`, and `[108,98]`. The four-chapter book needed the validation retry and then passed. Full generated texts were inspected for connected events and a gentle ending; these are smoke tests, not comprehensive editorial evaluation.
- An English iPhone simulator UI run created **Milo and the Star Light** in four chapters of 134, 148, 132, and 106 words. All text fields were inspected; publication produced four nonempty chapter files in the automatic library. The book survived app termination/relaunch and opened in the reader. Screenshots: [complete draft](qa/whole-book-draft-iphone.png), [reader after relaunch](qa/whole-book-reader-iphone.png).
- The Polish iPad UI verified Continue consent, automatic setup, existing-book copy, fixed storage destination, retry action, and family-sharing explanation with no library folder chooser.
- The iCloud-enabled Release device build was signed with the exact app container in its provisioning profile. PCC approval and successful cloud inference remain unverified.

Reproduce native checks:

```sh
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Physical iPhone/iPad checks remain for speed, story quality across ages/languages, model preparation, offline generation, background cancellation, Dynamic Type, and VoiceOver. Cloud checks require the entitlement grant and include network loss, quota, privacy UI, and successful generation. Simulator inference uses the Mac’s model and cannot establish hardware performance.
