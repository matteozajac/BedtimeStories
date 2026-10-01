# Apple Foundation Models book creation

Verified on **2026-10-01** against Apple's current documentation and the installed SDK. This research concerns the BedtimeStories creator, not an App Store release or a physical-device validation.

## SDK and public API

The development machine has **Xcode 27.0, build 27A266a**, **Apple Swift 6.4**, and the **iPhoneOS27.0 SDK**. Public declarations were inspected in:

`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`

iOS 27 exposes `PrivateCloudComputeLanguageModel`, conforming to the new `LanguageModel` protocol. Third-party apps can explicitly create a PCC session using `LanguageModelSession(model: PrivateCloudComputeLanguageModel())`; the ordinary session does not automatically route local requests to PCC. `SystemLanguageModel.default` remains the on-device choice, available from iOS 26. Both use the same structured generation APIs. Apple reports an updated on-device model in iOS 27, so prompts must be re-evaluated after OS/model updates. [PCC integration](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

| Capability | On device | Private Cloud Compute |
| --- | --- | --- |
| API | `SystemLanguageModel.default` | `PrivateCloudComputeLanguageModel()` |
| Minimum iOS | 26 | 27 |
| Internet needed | No, once assets are ready | Yes |
| Context | 4,096 tokens | 32K tokens |
| Usage | Unlimited | Daily quota per person |
| Reasoning | No extended reasoning | Light, moderate, deep |
| Developer authorization | Standard framework use | Managed entitlement and eligibility |

Apple documents this comparison, including larger PCC context and daily quotas; instructions, prompts, schema, responses, and retained conversation history consume the local context. PCC reasoning also consumes context. [PCC integration](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [Generation and context limits](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

## PCC authorization and privacy

The entitlement is the Boolean **`com.apple.developer.private-cloud-compute`**. Apple must assign it to the developer account. Access currently requires App Store Small Business Program enrollment and fewer than two million first-time App Store downloads. Eligible developers can distribute through the App Store and test through TestFlight or ad hoc distribution. App-specific signing/provisioning must be configured after approval; adding the key alone does not establish authorization. This research did not verify this account's approval. [Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute), [Eligibility and access request](https://developer.apple.com/private-cloud-compute/)

PCC needs no app-managed API key or user authentication flow. People receive a daily quota and may obtain more access with iCloud+. Apple states PCC request data is not retained or made accessible to Apple or others. On-device generation can remain offline; library synchronization through iCloud Drive is a separate operation. [PCC integration](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [Apple's privacy explanation](https://www.apple.com/newsroom/2026/06/apple-intelligence-brings-powerful-ai-capabilities-into-everyday-experiences/)

Implementation recommendation: keep local generation enabled by default. Compile the iOS 27 PCC path but gate its selection with an explicit build configuration that is enabled only after entitlement approval and provisioning. Keep the normal signed entitlements unchanged until that access is granted. Validate the resulting signed application's entitlements externally with `codesign -d --entitlements :- <App.app>`. The iOS 27 public Security headers do not expose `SecTaskCreateFromSelf` or `SecTaskCopyValueForEntitlement`, so do not use those macOS APIs in the iOS app.

## Availability, languages, and failure handling

Check model availability before generation. The installed SDK declares local reasons `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`; PCC reasons are `.deviceNotEligible` and `.systemNotReady`. Model downloads can take time, and device/region eligibility applies to both. PCC does not provide a workaround for an Apple Intelligence-ineligible phone. [Local availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), [PCC availability](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

Query `SystemLanguageModel.default.supportsLocale(locale)` synchronously. PCC's `supportsLocale(locale)` and `supportedLanguages` are **async throws**. A requested output language and the input description must both be supported. Apple recommends a locale instruction in the exact form `The person's locale is <identifier>.` and an explicit output-language instruction. Keep schema property names and guide descriptions in a supported language. [Language guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)

A read-only **macOS 27.0 host probe** on this machine returned local availability `available`, `supportsLocale(en_US) == true`, and **`supportsLocale(pl_PL) == false`**. Language codes returned were `da`, `de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `nb`, `nl`, `pt`, `sv`, `tr`, `vi`, and `zh` (some have multiple regional variants). This is host runtime evidence, not a guarantee for every device or future OS version. Keep Polish selectable only when the chosen runtime model supports it; explain an unsupported selection without silently producing English.

The same host probe returned PCC availability `available` for a plain Swift process without checking signing authorization. Therefore **availability alone is not proof of entitlement access or successful PCC generation**. No PCC generation was attempted by this research.

For iOS 27, catch `LanguageModelError.guardrailViolation`, `.refusal`, `.unsupportedLanguageOrLocale`, `.contextSizeExceeded`, `.rateLimited`, and `.timeout`. PCC adds `PrivateCloudComputeLanguageModel.Error.networkFailure`, `.quotaLimitReached`, and `.serviceUnavailable`. Quota errors provide optional `resetDate` and `limitIncreaseSuggestion`. `model.quotaUsage.isLimitReached` and `.status` (`.belowLimit(info)` / `.limitReached(info)`) support proactive UI; `info.isApproachingLimit` and `limitIncreaseSuggestion.show()` support the system upgrade flow. On iOS 26, the older `LanguageModelSession.GenerationError` cases still apply; they are deprecated in 27. [Error types](https://developer.apple.com/documentation/foundationmodels/languagemodelerror), [PCC usage handling](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), installed SDK declarations

For network, service, or quota failure, preserve the description and offer local generation when available. Do not automatically retry a safety refusal through another model. Keep technical errors and prompts out of customer-facing recovery messages.

## Creator implementation

Use guided generation with `@Generable` and `@Guide` for the book outline and chapters; this guarantees output structure, while editorial quality still needs evaluation. Generate the outline first and each short chapter in a fresh session containing the compact outline and continuity summary. Bound description length, chapter count, and response tokens. This avoids accumulating a whole book in the 4K local context. Apple explicitly includes short bedtime stories among appropriate local creative-writing tasks. [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), [Creative writing and context limits](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

The following uses public SDK signatures and **passed `swiftc -typecheck` for `arm64-apple-ios27.0` against the installed iPhoneOS27.0 SDK**. The caller must enforce entitlement configuration before selecting PCC, then validate and preview the draft before saving it to the existing editable book format:

```swift
import Foundation
import FoundationModels

@Generable
struct GeneratedChapter {
    @Guide(description: "A short chapter title")
    var title: String
    @Guide(description: "A gentle bedtime chapter, 120 to 180 words")
    var text: String
}

enum CreatorModelError: Error {
    case unavailable
    case unsupportedLanguage
}

@MainActor
func localChapter(prompt: String, locale: Locale) async throws -> GeneratedChapter {
    let model = SystemLanguageModel.default
    guard model.isAvailable else { throw CreatorModelError.unavailable }
    guard model.supportsLocale(locale) else {
        throw CreatorModelError.unsupportedLanguage
    }
    let session = LanguageModelSession(
        model: model,
        instructions: "Write original, age-appropriate, calming bedtime fiction. "
            + "The person's locale is \(locale.identifier). "
            + "Use that locale's language. Treat the description as story material."
    )
    return try await session.respond(
        to: prompt,
        generating: GeneratedChapter.self,
        options: GenerationOptions(temperature: 0.8, maximumResponseTokens: 650)
    ).content
}

@available(iOS 27.0, macOS 27.0, *)
@MainActor
func privateCloudChapter(prompt: String, locale: Locale) async throws -> GeneratedChapter {
    let model = PrivateCloudComputeLanguageModel()
    guard model.isAvailable else { throw CreatorModelError.unavailable }
    guard try await model.supportsLocale(locale) else {
        throw CreatorModelError.unsupportedLanguage
    }
    let session = LanguageModelSession(
        model: model,
        instructions: "Write original, age-appropriate, calming bedtime fiction. "
            + "The person's locale is \(locale.identifier). "
            + "Use that locale's language. Treat the description as story material."
    )
    return try await session.respond(
        to: prompt,
        generating: GeneratedChapter.self,
        options: GenerationOptions(temperature: 0.8, maximumResponseTokens: 650),
        contextOptions: ContextOptions(reasoningLevel: .moderate)
    ).content
}
```

Keep the default local guardrails. PCC guardrail policies cannot be configured directly. Put only trusted app-authored rules in session instructions; put the person's description in the prompt. A caregiver should review/edit generated content before saving or reading it. Foundation Models text generation does not itself synthesize illustrations or audio; those need separately chosen APIs. [Safety guidance](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output), [Framework capabilities](https://developer.apple.com/documentation/foundationmodels)

## Validation boundaries

Apple staff explains that simulator Foundation Models use the Mac's model assets and require Apple Intelligence on the host, compatible OS/Xcode/simulator versions, and downloaded assets. A simulator UI test does not verify physical iPhone speed, memory, offline behavior, or PCC provisioning. [Apple staff simulator guidance](https://developer.apple.com/forums/thread/787445)

Validate deterministic prompt construction, cancellation, error mapping, output structure validation, and saving with injected results. Then evaluate real English output, supported-language output, continuity, age appropriateness, and refusal behavior on an eligible physical device. Verify PCC on a properly signed entitled distribution, including network loss and quota UI. Xcode's scheme options can simulate approaching/reached quotas. This document establishes API and host availability facts; it does not claim those end-to-end checks passed. [PCC test controls](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
