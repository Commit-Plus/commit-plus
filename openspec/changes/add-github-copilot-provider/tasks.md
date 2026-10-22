# Tasks

## 1. Language server spike

- [ ] 1.1 Pin a `@github/copilot-language-server` version and confirm, by driving it from a scratch script over stdio, the exact JSON-RPC methods for sign-in initiate/confirm/status, sign-out, model listing, and a single-turn chat. Verify by recording the request and response shapes in the design's Decisions section.
- [ ] 1.2 Determine whether that version ships a standalone macOS executable (arm64 and x86_64) or needs Node. Verify by launching it on this Mac without a global Node install, and record the result in the design.

## 2. Runtime management

- [ ] 2.1 Add `CopilotLanguageServerRuntime`, modeled on `GitRuntimeManager`/`GitLFSRuntime`, that downloads, verifies the checksum of, caches, and locates the pinned server under Application Support. Verify with a new `CopilotLanguageServerRuntimeTests` class covering cache hit, checksum mismatch, and download failure.
- [ ] 2.2 Add `actor CopilotLanguageServerClient` with JSON-RPC framing, request correlation, lazy start, one restart after unexpected exit, and termination on app quit. Verify with `CopilotLanguageServerClientTests` using a fake process transport (framing, correlation, restart).

## 3. Account-based provider support

- [ ] 3.1 Add `AIProviderBilling.connectedAccount` and connection state in `AIProviderController` (signed-in username, sign-in pending, sign-in required), so configured means signed in for these providers. Skip this task if the ChatGPT change already landed it. Verify with `CloudAIProviderTests` plus new cases asserting that connected-account providers are selectable only when signed in and available.
- [ ] 3.2 Extend `AIProvidersSettingsView` and `AIProviderConfigurationSheet` so connected-account providers appear in "Add Provider…" and the Providers table, and the sheet shows an Account section (sign in, device code via `GitProviderDeviceAuthorizationView`, cancel, sign out) instead of an API key. Verify with an app build.

## 4. Copilot provider

- [ ] 4.1 Add `GitHubCopilotProvider` (`AIProviderID.githubCopilot`, `.connectedAccount`, no Pro gate, `supportsRepositoryAgent = false`), implementing commit-message, repository chat, and conflict resolution through the client, and register it in `AIProviderRegistry.live`. Verify with `GitHubCopilotProviderTests` using a fake client: prompt routing, the model fallback when a saved model disappears, and no token in any model request content.
- [ ] 4.2 Map Copilot errors (not signed in, no entitlement, quota exhausted, rate limited, server unavailable) to `CommitMessageGenerationError` and availability states with the messages required by the spec. Verify with error-mapping cases in `GitHubCopilotProviderTests`.
- [ ] 4.3 Implement removal: confirmation, sign-out through the server, and fallback of the default provider to Apple Intelligence. Verify with a `CloudAIProviderTests` case for default-provider fallback after removal.
- [ ] 4.4 Add the Copilot logo asset and the telemetry toggle with its footer text in the sheet. Verify with an app build.

## 5. Integration checks

- [ ] 5.1 Run `xcodebuild … -only-testing:macgitTests/CloudAIProviderTests -only-testing:macgitTests/CommitPlusAISelectionPolicyTests -only-testing:macgitTests/GitHubCopilotProviderTests -only-testing:macgitTests/CopilotLanguageServerClientTests -only-testing:macgitTests/CopilotLanguageServerRuntimeTests test` and verify that all pass.
- [ ] 5.2 Manual UI review in Settings → AI:
  - Add Copilot with a Copilot Free account and with a paid account, cancel a pending sign-in, and check the device-code layout.
  - Generate a commit message and ask a repository chat question.
  - Exhaust or simulate the quota error, remove Copilot while it is the default, and confirm the fallback.
  - Verify by recording the results in the PR description.
- [ ] 5.3 Confirm settings sync uploads no Copilot state. Verify by inspecting the encoded `CloudSettingsDocument` in a debug build after connecting Copilot.
