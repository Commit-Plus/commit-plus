# Commit+ AI Phase 2: macOS Integration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. Use SwiftUI Pro guidance for the focused view/data-flow changes; do not delegate unless chosen by the user.

**Goal:** Add a Pro-only Commit+ AI option everywhere AI providers are selected and route every existing AI workflow through the managed backend with shared allowance presentation.

**Architecture:** Extend `CommitMessageAIProvider` and `AIProviderRegistry`; do not replace the current provider controller or Git harness. A session-scoped managed client obtains Firebase bearer tokens, decodes the frozen HTTP/SSE contract, and updates allowance through a main-actor controller. Views render state and invoke callbacks.

**Tech Stack:** Swift, SwiftUI, existing Firebase Auth SDK, URLSession, existing XCTest fixtures; no new third-party frameworks.

---

## Execution status (2026-09-14)

Implementation and build verification are complete on `codex/commit-plus-ai-macos`. See [verification evidence](2026-09-13-commit-plus-ai-macos-verification.md). Checked test items mean coverage was authored and compiled; no test execution or runtime UI verification is claimed. The 22 new tests are grouped into contract, client, provider, selection and usage-controller files rather than one file per model. Phase 3 owns live endpoint/configuration and runtime verification.

## Root and prerequisites

Root: `/Users/thanhtran/Project/Commit+/macgit`. Branch: `codex/commit-plus-ai-macos`, created from clean `main` after Phase 1's contracts and documentation have been integrated. Follow AGENTS.md before switching branches. The current design branch is not a phase-work base.

Phase 1's redacted HTTP fixtures are the protocol reference. Copy the small test fixtures into `macgitTests/Fixtures/CommitPlusAI/`; do not reference private backend files at app runtime. Every new `.swift` file needs the complete existing AGPL header. Do not introduce upstream API keys, prices or selectable model IDs into the client.

Verification follows the user's macOS instruction: build, do not launch the app, and do not rerun a test suite that crashes at bootstrapping. Add meaningful XCTest coverage for the new contracts/policies, but do not claim it ran merely because a build succeeded. Live UI and hosted test execution remain separate evidence.

## Task 1: Provider identity and separate managed access policy

**Modify:** `macgit/Models/AIProviderID.swift`, `macgit/App/AIProviderController.swift`, `macgit/Services/AIProviderRegistry.swift`, `macgit/App/macgitApp.swift`.
**Create:** `macgit/Models/CommitPlusAISelectionPolicy.swift`, `macgitTests/CommitPlusAISelectionPolicyTests.swift`.
**Inspect, preserve:** `macgit/Models/AIProviderDescriptor.swift`, `macgit/Models/FeatureAccessPolicy.swift`, `macgitTests/CloudAIProviderTests.swift`, `macgitTests/FeatureAccessPolicyTests.swift`.

- [x] Add `static let commitPlusAI = Self(rawValue: "commit-plus-ai")`. Reuse existing `AIProviderBilling.commitPlus` and `requiresProAccess`; do not add a competing billing enum or mark managed AI as BYOK.
- [x] Add a small pure selection policy and its complete truth-table test:

```swift
struct CommitPlusAISelectionPolicy {
    static func canSelect(isSignedIn: Bool, hasProAccess: Bool) -> Bool {
        isSignedIn && hasProAccess
    }
}
```

```swift
func testManagedSelectionRequiresSignedInPro() {
    XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: false, hasProAccess: false))
    XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: false, hasProAccess: true))
    XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: true, hasProAccess: false))
    XCTAssertTrue(CommitPlusAISelectionPolicy.canSelect(isSignedIn: true, hasProAccess: true))
}
```

- [x] Inject a dedicated managed-access closure from `macgitApp` based on authenticated account plus active Pro entitlement. Existing `restrictedProviderAccess` currently evaluates `.aiBringYourOwnKey`; preserve that path and its remote feature policy. Do not couple managed entitlement to whether a user may configure a BYOK key.
- [x] Handle `.commitPlus` explicitly in `canSelect` before legacy cloud/key checks. Managed selection depends on Pro access, not an API key or remaining allowance. Selection and inference availability are separate: an exhausted Pro user may retain/select Commit+ AI while new inference is blocked. Keep the existing `isGenerating` menu restriction.
- [x] Apply the same managed gate inside `selectProvider` and `validateProviderAccess`, so programmatic calls cannot bypass UI restrictions. Loading a persisted selection may retain an unavailable Commit+ AI ID for explanation, but must not authorize inference or switch to another provider.
- [x] Change credential/model discovery and `configurationDrafts` to operate on `.bringYourOwnKey` instead of all `.cloud` providers. Guard `saveAPIKey`, removal, and draft application against the managed ID. Preserve all existing BYOK checks, custom model values, and key removal behavior.
- [x] Add controller regression tests asserting managed Pro can select with an empty credential store, Free cannot select, exhaustion does not erase selection, and each legacy provider retains its existing selection behavior. Include account logout with a persisted managed selection.

## Task 2: Session-scoped HTTP transport and allowance state

**Create:** `macgit/Models/CommitPlusAIAllowance.swift`, `macgit/Models/CommitPlusAIError.swift`, `macgit/Models/CommitPlusAIWireMessage.swift`, `macgit/Services/CommitPlusAIClient.swift`, `macgit/Services/CommitPlusAIEventDecoder.swift`, `macgit/Services/CommitPlusAITokenProvider.swift`, `macgit/App/CommitPlusAIUsageController.swift`, `macgitTests/CommitPlusAIClientTests.swift`, `macgitTests/CommitPlusAIEventDecoderTests.swift`, `macgitTests/CommitPlusAIUsageControllerTests.swift`.
**Modify:** `macgit/App/macgitApp.swift`, `macgit/App/AIProviderController.swift`; the project's existing app configuration location for one public backend base URL.

- [x] Define `CommitPlusAIAllowance` as `Decodable, Equatable, Sendable`, matching Phase 0 units and timestamps. Use `Int64` for server integer units and `Decimal` only for presentation conversion. Reject invalid denominators, negative counters and inconsistent availability.
- [x] Define the concrete wire request/response types for the three Phase 0 routes. Restrict `operation` to the four supported values. Include the request UUID, version and messages/tools, without upstream provider/model/key fields. Keep role/tool-call payload types in separate focused model files if needed.
- [x] Implement a Firebase token provider using the current Firebase user ID token, not the custom web sign-in token. Inject it into an actor-backed managed HTTP client. Capture UID/session generation at operation start and check it again before applying any response, so logout or switching accounts cannot expose another account's allowance/result.
- [x] Bind the public function base URL through the app's build configuration using the same validation principles as `CommitPlusWebConfiguration`. Reject non-HTTPS production URLs; permit localhost only through explicit test/development configuration. Do not build a URL containing provider secrets.
- [x] Use URLSession streaming to incrementally decode SSE with UTF-8 boundary handling. Accumulate text/tool deltas by stable identity; expose a completed result only on the contract's terminal event. Include a test feeding each fixture one byte at a time and assert final equality with the unsplit fixture. Partial tool JSON must never become a runnable tool call.
- [x] Create one UUID per model invocation and retain it across transport status checks. On an ambiguous failure query request status with the same ID. Never silently replace it with a fresh invocation. A completed status without retained output gives a clear recovery message; a user-initiated new send creates a new ID and may consume credit.
- [x] Allow a single Firebase token refresh/retry only for a definitive pre-admission 401, preserving the request ID. Do not retry HTTP 409/429 or a broken stream as a new inference. Map `pro_required`, `credits_exhausted`, `provider_unavailable`, `accounting_pending` and `request_already_completed` to typed app errors with actionable copy.
- [x] Implement `CommitPlusAIUsageController` with main-actor isolation, session-scoped `loading`, `loaded`, and `unavailable` state, and an injected async allowance loader. Use the existing ObservableObject integration convention rather than migrating unrelated app ownership. Test: initial load, a real zero balance, load failure, delayed result after account switch, and concurrent refresh coalescing.
- [x] Refresh on entering Settings, selecting managed AI, application activation and terminal inference result. Session changes clear prior allowance immediately. Existing other-provider availability refresh must not become serially blocked behind a slow managed network call.

## Task 3: Implement every provider operation using existing prompts and decoders

**Create:** `macgit/Services/CommitPlusAIProvider.swift`, `macgitTests/CommitPlusAIProviderTests.swift`.
**Modify:** `macgit/Services/AIProviderRegistry.swift` and injection in `macgit/App/AIProviderController.swift`.
**Reuse without moving Git execution:** `macgit/Services/CloudAIProviderSupport.swift`, `macgit/Services/RepositoryAIPrompt.swift`, `macgit/Services/RepositoryAIAgentHarness.swift`, the existing conflict prompt/response types.

- [x] Give the provider the following descriptor; the input character budget preserves current cloud context sizing and is not a backend cost bound:

```swift
let descriptor = AIProviderDescriptor(
    id: .commitPlusAI,
    displayName: "Commit+ AI",
    systemImage: "sparkles",
    detail: "Cloud · Included with Pro",
    dataProcessing: .cloud,
    billing: .commitPlus,
    requiresProToConfigureAPIKey: false,
    defaultModel: nil,
    inputCharacterBudget: 12_000,
    isImplemented: true
)
```

- [x] Implement `availability()` using managed entitlement/service/allowance state. A missing key must never be the reason it is unavailable. Keep selection eligibility separate from availability for inference.
- [x] Implement `generateCommitMessage`: reuse `CloudCommitMessagePrompt.jsonInstructions` and `userPrompt(for:)`, request operation `commit_message`, decode final text through `CloudCommitMessageResponse.decode(from:).formatted()`. Fixture test must assert exact formatted subject/body, not merely nonempty text.
- [x] Implement `generateRepositoryResponse` and `streamRepositoryResponse`: use `RepositoryAIPrompt.instructions(for:)` and `userPrompt(for:)`, operation `repository_response`, and the existing structured-answer decoder. Set Phase 0's `responseFormat` to `json_object` when `requiresStructuredResponse` is true and `text` otherwise. This is an operation capability, not a user-selected model setting. Preserve existing structured-response behavior instead of emitting incomplete JSON as final answer text.
- [x] Implement `generateRepositoryAgentTurn` and set `supportsRepositoryAgent` to true. Convert existing agent messages and `RepositoryAIAgentToolSchema` into the wire payload, preserving tool-call IDs and semantic tool schemas. Convert only completed, validated returned calls to `RepositoryAIAgentTurn`. Keep the harness's tool limit, offline Git query policy, local confirmation flow and state checks intact.
- [x] Implement `generateConflictResolution` explicitly with operation `conflict_resolution`, current conflict context builder and response decoder. Do not rely on a default protocol method that labels its billing event as ordinary repository chat. Verify malformed or incomplete conflict output cannot be applied.
- [x] Register Commit+ AI once in `.live`, injecting the managed client without credential/model stores. Test each operation's payload, decoder, error mapping and cancellation. Assert operation tags and unique per-invocation IDs across a multi-turn agent conversation.
- [x] Keep `AIProviderController`'s repository/provider fingerprint checks after awaiting results. Add account/session freshness to managed calls rather than removing existing context-change guards.

## Task 4: Consistent selector, settings and disabled-send presentation

**Modify:** `macgit/Views/FileStatus/AIProviderMenu.swift`, `macgit/Views/Common/AIProvidersSettingsView.swift`, `macgit/Views/FileStatus/FileStatusView.swift`, `macgit/Views/FileStatus/CommitSheetView.swift`, `macgit/Views/MainWindow/RepositoryAIChatView.swift`, `macgit/Views/Common/ConflictMergeToolView.swift` only where shared availability is not already respected.
**Create:** `macgit/Views/Common/CommitPlusAIUsageView.swift`.

- [x] Show the managed menu entry as `Commit+ AI — Pro`. In model label mode return `Commit+ AI`, never `Default` or `On-device`. Managed menu help explains Pro access, allowance or service status and never suggests entering a key.
- [x] Remove the selected managed provider's generic Settings `Model` row; render a managed section showing `Included with Pro`, remaining credits/500, a progress bar, reset time and concise cloud-processing disclosure. Do not generate a managed draft for `CloudAIProviderSettingsSection`.
- [x] Render available units as the backend's reserve-aware value, with up to two decimals. Positive values below 0.01 credit display `<0.01` instead of a misleading zero. Progress clamps for display only; malformed counters fail decoding rather than being silently repaired. VoiceOver reads available credits and reset date without depending on color.
- [x] At exhaustion disable managed Send/Generate through shared availability and show `Your AI credits are used up. Credits renew on …`. If entitlement ends before renewal and `resetsAt` is null, do not promise another grant. Keep the selection and let the user explicitly choose BYOK.
- [x] On load failure show `Usage unavailable` and a retry action; never show 500 or zero as a fallback. If usage is pending, explain that available credits account for the in-flight reservation. No API/model implementation details belong in this user-facing view.
- [x] Confirm the shared menu appears in Settings, FileStatus and RepositoryAIChatView using `rtk rg -n 'AIProviderMenu' macgit/Views`. Audit generation affordances in CommitSheet and ConflictMergeToolView even though they do not each define another menu. Any new selector discovered during execution uses the same managed gate.
- [x] Refresh Settings footer copy so it describes the currently supported AI workflows, including conflict resolution, without advertising future-only behavior. Preserve the layout and controls of existing BYOK sections.

## Task 5: Build and record verification

**Create:** `docs/superpowers/plans/2026-09-13-commit-plus-ai-macos-verification.md` during execution.

- [x] Verify new files have AGPL markers and are included through the project's existing Xcode file-discovery convention. Do not hand-edit project membership unless the project actually requires it.
- [x] Run `rtk proxy git diff --check` and resolve whitespace issues before building. Run a single sequential macOS build:

```sh
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

- [x] Expect exit 0 and `BUILD SUCCEEDED`. Do not launch Commit+. Do not rerun a crashing hosted XCTest bootstrap. Record whether new XCTest cases were executed separately or only authored; the build does not prove tests or runtime UI behavior.
- [x] Review the fixture coverage for all five provider protocol methods, account-switch races, Pro/Free selection, no key controls, exhausted allowance, and unchanged BYOK. Record any unexecuted hosted tests or manual UI checks as pending evidence in Phase 3, not passing checks.
- [x] Commit explicit changed files on the feature branch with a message describing the managed provider and allowance UI. Update roadmap status only with actual validation evidence; do not merge or launch as part of this task.
