# Commit+ AI macOS integration verification

Date: 2026-09-14. Branch: `codex/commit-plus-ai-macos`.

## Implemented behavior

- The live app registers Commit+ AI as a managed cloud provider. Selection requires a signed-in Pro account and remains available to Pro users with exhausted credits. Persisted selection does not authorize generation after logout/downgrade.
- Managed access is independent of BYOK feature policy. Managed AI has no credential drafts, personal key storage or model controls; existing BYOK providers retain their configuration path.
- The provider implements commit messages, repository answers, streamed repository answers, agent turns and conflict resolution through the existing prompts/decoders. Agent tools and Git approval/execution remain in the existing local harness.
- The HTTP client uses Firebase ID tokens and a captured account/session generation. A definitive 401 may refresh once with the same request UUID. Ambiguous responses trigger a status GET for the original UUID; they never silently create another inference. Lost output and unknown accounting outcomes have explicit recovery messages.
- SSE decoding preserves split UTF-8 and accumulates text/tool fragments. Partial tools cannot execute: the terminal payload must match accumulated content and pass complete JSON/tool validation.
- Allowance decoding validates integer units, timestamps, denominator and reserve-aware accounting. Settings shows remaining credits, renewal, pending reservations, loading/error/retry states and cloud disclosure. Old reads cannot overwrite a terminal balance or a different account's state.
- Settings, File Status and Repository AI share `AIProviderMenu`. Commit Sheet already respects shared availability; Repository AI Send and Conflict Merge AI actions now also disable on unavailable allowance/provider state.

## Verification evidence

- New files use Xcode synchronized-folder membership and include AGPL headers (17 Swift files checked).
- `rtk proxy git diff --check`: passed.
- `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build-for-testing`: passed (`TEST BUILD SUCCEEDED`, exit 0).
- `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`: passed (`BUILD SUCCEEDED`, exit 0).
- 22 targeted XCTest cases are authored. They cover selection truth table, no-key Pro selection/exhaustion/logout, malformed accounting, fractional display, null tool-message content, bytewise SSE and truncation, URL configuration, all five provider methods, structured streaming, agent tool history, cancellation, malformed conflict output, transport retry/status identity, session rejection, allowance failure/races and refresh coalescing.
- Existing BYOK tests are preserved and included in test-target compilation. Source review confirms BYOK key/model discovery and access policies remain separate from managed allowance.

No XCTest cases were executed and Commit+ was not launched, following the user's build-only instruction. Test-target compilation is not runtime evidence.

## Configuration and Phase 3 handoff

`COMMIT_PLUS_AI_BASE_URL` feeds the public `CommitPlusAIBaseURL` Info.plist key. Debug and Release intentionally default to an empty value until a backend endpoint has been deployed and verified. Set it to the HTTPS base URL whose child routes are `v1/allowance`, `v1/inference` and `v1/requests/{id}`. No provider/model/key is configured in the app. Production URL validation rejects HTTP, embedded credentials, query parameters and fragments; localhost HTTP is available only through the explicit test validation option.

Before rollout, Phase 3 must supply the verified endpoint, perform live DeepSeek/Groq requests, verify Firebase session changes and Polar/credit reconciliation across the app/backend, execute the authored tests in a working hosted environment when authorized, and review Settings/menu/disabled-send/VoiceOver behavior in the running app. Runtime coverage of structured answers, multi-turn tool history and cancellation remains part of this integration verification. No deployment, remote push or Phase 2 merge is included here.
