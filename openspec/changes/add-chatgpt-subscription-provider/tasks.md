# Tasks

## 1. Registration and verification

- [ ] 1.1 Verify against OpenAI's live "Sign in with ChatGPT" documentation:
  - authorization, token, and refresh endpoints;
  - plan-usage scope names and the resource indicator;
  - accepted redirect URI types (custom scheme or loopback);
  - the inference endpoint and request shape;
  - the error codes for cap reached, revoked grant, and ineligible plan.
  Verify by recording them in the design's Decisions section.
- [ ] 1.2 Register Commit+ as an open-source client with OpenAI (requires the maintainer's OpenAI account; needs explicit user action). Store the issued client ID as a build setting surfaced through `Info.plist`. Verify that a debug build reads it and that a build without it shows "Not configured in this build".

## 2. Account-based provider support

- [ ] 2.1 Add `AIProviderBilling.connectedAccount` and connection state in `AIProviderController`, so configured means signed in for these providers. Skip this task if the Copilot change already landed it. Verify with `CloudAIProviderTests` plus new cases asserting that connected-account providers are selectable only when signed in, available, and allowed by gating.
- [ ] 2.2 Extend `AIProvidersSettingsView` and `AIProviderConfigurationSheet` so connected-account providers appear in "Add Provider…" and the Providers table, and the sheet shows an Account section (sign in, waiting state with Cancel, account and plan, disconnect) instead of an API key. Verify with an app build.

## 3. OAuth and token session

- [ ] 3.1 Implement the PKCE authorization flow, reusing `GitProviderOAuthSession`/`GitProviderOAuthCallback` helpers and the external-event callback path, with a state check and granted-scope verification. Verify with `ChatGPTAccountSessionTests` covering state mismatch, denied consent, and a missing plan-usage scope.
- [ ] 3.2 Add `actor ChatGPTAccountSession` for Keychain storage of the token set, proactive refresh with a single in-flight refresh, and clearing on refresh rejection. Verify with `ChatGPTAccountSessionTests` using an in-memory Keychain store: concurrent requests share one refresh, a rejected refresh leaves no stale token, and nothing is written to `UserDefaults`.

## 4. ChatGPT provider

- [ ] 4.1 Extract the OpenAI request, streaming, and agent-turn handling from `OpenAICommitMessageProvider` into a shared transport parameterized by endpoint, headers, and credential source, with no behavior change for the API-key provider. Verify that the existing `CloudAIProviderTests` OpenAI cases still pass unchanged.
- [ ] 4.2 Add `ChatGPTSubscriptionProvider` (`AIProviderID.chatGPTSubscription`, `.connectedAccount`, `requiresProToConfigureAPIKey = true`, `supportsRepositoryAgent = true`) using the shared transport with session tokens, and register it in `AIProviderRegistry.live`. Verify with `ChatGPTSubscriptionProviderTests`: tokens only appear in the authorization header and never in the request body, and agent turns decode.
- [ ] 4.3 Map cap-reached, revoked-grant, ineligible-plan, and sign-in-required responses to `CommitMessageGenerationError` and availability states with no fallback to another provider. Verify with error-mapping cases in `ChatGPTSubscriptionProviderTests`.
- [ ] 4.4 Enforce Pro gating for configuration and selection, while still allowing disconnect after Pro lapses. Verify with `CommitPlusAISelectionPolicyTests` cases for a Free user, a lapsed Pro user, and the policy-unavailable fallback.
- [ ] 4.5 Implement disconnect: confirmation, Keychain deletion, and fallback of the default provider to Apple Intelligence. Verify with a `CloudAIProviderTests` case.

## 5. Integration checks

- [ ] 5.1 Run `xcodebuild … -only-testing:macgitTests/CloudAIProviderTests -only-testing:macgitTests/CommitPlusAISelectionPolicyTests -only-testing:macgitTests/ChatGPTAccountSessionTests -only-testing:macgitTests/ChatGPTSubscriptionProviderTests test` and verify that all pass.
- [ ] 5.2 Manual UI review in Settings → AI:
  - As a Free user, check the Pro prompt.
  - As Pro, sign in with a Plus account, cancel a pending sign-in, and check the connected layout.
  - Generate a commit message, run a repository agent mutation and confirm its prompt, and disconnect while ChatGPT is the default.
  - Verify by recording the results in the PR description.
- [ ] 5.3 Confirm no ChatGPT token appears in logs or the encoded `CloudSettingsDocument`. Verify by inspecting debug logs and the encoded document after a full sign-in and request.
