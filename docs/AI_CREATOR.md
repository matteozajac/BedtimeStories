# Create a book from an idea

Open **Library → + → Book Creator → Create from an Idea** (or open the creator from the welcome screen). Enter a description up to 600 characters, choose English or Polish, the reader's age, and 1–4 chapters. Select a processing mode and tap **Create Story Draft**. The model writes an original title, summary, outline, and short chapter text. A completed draft opens in the existing editor, where you can read and edit it, add photos, record narration, and choose **Add to Library**. Text generation does not create pictures or audio.

The description is saved in this app's device preferences. The outline is saved as a local draft, and each completed chapter is saved atomically before the next chapter begins. **Stop Creating**, leaving the screen, or moving the app to the background cancels generation. On failure or cancellation, **Open Saved Draft** opens the saved portion; it is also available under **Your Drafts** after relaunch. Starting another draft leaves the previous one intact. Generation does not replace existing books or publish to the shared library automatically. After the usual **Add to Library** action, the generated book uses the same `book.json`, chapter Markdown files, and `.bedtimestory` export/import format as a manually written book.

## Processing and languages

**On This Device** is the default and uses `SystemLanguageModel.default`. It needs an Apple Intelligence-capable device, Apple Intelligence enabled, and downloaded model assets. Creation works offline once those assets are ready. **Private Cloud Compute** explicitly uses `PrivateCloudComputeLanguageModel` and sends the story description, compact book outline, and chapter continuity to Apple's service. It requires internet access, model availability, remaining quota, and an entitled app build. Selecting a mode never silently switches to the other mode, including after a refusal, network error, or quota failure.

English and Polish are offered as output languages. The selected model's runtime `supportsLocale` decides whether generation can proceed. The local model on this Mac currently supports English and does **not** support Polish; the app explains unsupported selections instead of generating another language. PCC language checks run asynchronously before a request. The UI itself is translated into English and Polish. Model/OS updates can change language support; see [the dated primary-source research](FOUNDATION_MODELS_RESEARCH.md).

Each generation request uses a fresh session. Chapter prompts include only the brief, a bounded outline, and the previous chapter's short continuity note. The local path counts prompt, instructions, and schema tokens and reserves room for its response before inference. Default Apple guardrails remain enabled, trusted app instructions are separate from story data, and generated fields are validated before saving. Generation errors use app-owned recovery messages without displaying technical errors or echoing private prompts.

## Enabling Private Cloud Compute

The ordinary app build deliberately keeps cloud creation unavailable until authorization is configured. Apple's `availability` API does not establish that the app has the required entitlement. Apple must grant the Boolean managed entitlement `com.apple.developer.private-cloud-compute` to the developer account; current eligibility and distribution requirements are linked in [the research](FOUNDATION_MODELS_RESEARCH.md).

After Apple grants access, enable the capability for bundle ID `com.matteozajac.bedtimestories` and regenerate its distribution provisioning profiles. Use `Config/PrivateCloudCompute.xcconfig` for the intended app build configuration or pass it to `xcodebuild -xcconfig Config/PrivateCloudCompute.xcconfig`. It adds `Config/PrivateCloudCompute.entitlements` and the `BEDTIME_PRIVATE_CLOUD_COMPUTE` Swift compilation condition together. Do not enable the condition without the corresponding granted signing entitlement. If other entitlements are introduced, merge them into the opt-in file before using it.

Verify the exported app with `codesign -d --entitlements :- <App.app>` and inspect its embedded provisioning profile for the same grant. Test on an eligible device through an Apple-supported entitled distribution (TestFlight/ad hoc/App Store). A signing-disabled build proves the code compiles; it does not establish PCC authorization or successful cloud generation.

## Validation

Verified on **1 October 2026** with Xcode 27.0 / iOS 27:

- Ordinary Debug simulator app build passed.
- All **14 native tests** passed on each dedicated iPhone and iPad simulator: 7 existing library/player/manual-creator tests and 7 new generation tests.
- The **Release iOS device build with the PCC opt-in configuration** passed with signing disabled. The compiler invocation contains `-DBEDTIME_PRIVATE_CLOUD_COMPUTE`; no signing/provisioning or cloud request is established by this result.
- Real local generation through the English iPhone simulator UI created **Milo and the Shining Star**, with 3 chapters of 140, 117, and 123 words. The draft opened in the editor, survived termination/relaunch, was published to that simulator's local `Documents/QA Library`, and opened in the existing reader. All generated chapter Markdown files were present, and the draft was removed only after successful publication. This was a smoke test of one generated story, not a broad editorial quality evaluation.
- Polish iPad UI checks covered the new form, options, the runtime model-preparation message, selecting PCC, and its translated unavailable-build message. Tapping the unavailable creation action did not start generation. The iPhone accessibility backend returned empty snapshots, so iPhone navigation used inspected screenshots and coordinates; iPad accessibility labels were available.
- `git diff --check` passed.

Screenshots: [generated draft](qa/ai-generated-draft-iphone.png), [reading the generated book](qa/ai-generated-reader-iphone.png), [Polish creator on iPad](qa/ai-creator-ipad-pl.png), [PCC gate on iPad](qa/ai-cloud-gate-ipad-pl.png).

Reproduce automated validation:

```sh
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project BedtimeStories.xcodeproj -scheme BedtimeStories \
  -configuration Release -destination 'generic/platform=iOS' \
  -xcconfig Config/PrivateCloudCompute.xcconfig CODE_SIGNING_ALLOWED=NO build
```

The new native integration suite injects generator responses rather than consuming model quota. It checks generation-to-draft recovery, chapter continuity, existing book publication/export/import, preserving completed chapters after cancellation or cloud quota failure, keeping old drafts when starting again, blank/oversized descriptions, unavailable models, invalid outlines/chapters, failed persistence, app-owned safety-refusal messages, and the ordinary build's cloud gate.

Real iPhone/iPad checks should cover story quality and continuity across 1–4 chapters, age/language suitability, first model download, Apple Intelligence disabled, unsupported language, offline local generation, cancellation/backgrounding, larger Dynamic Type, and VoiceOver. PCC requires separate entitled-device validation for network loss, daily quota, service unavailability, privacy UI, and successful generation. Simulator generation uses the Mac's model and does not establish physical-device performance.
