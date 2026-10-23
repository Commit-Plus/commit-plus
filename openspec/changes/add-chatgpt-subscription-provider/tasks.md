# Tasks

## 1. Registration and verification

- [x] 1.1 Verify against OpenAI's live "Sign in with ChatGPT" documentation:
  - authorization, token, and refresh endpoints;
  - plan-usage scope names and the resource indicator;
  - accepted redirect URI types (custom scheme or loopback);
  - the inference endpoint and request shape;
  - the error codes for cap reached, revoked grant, and ineligible plan.
  Verify by recording them in the design's Decisions section.
- [x] 1.2 Add `ChatGPTAuthConfiguration` with the verified endpoints, scopes, resource, loopback redirect path, and agent name. Use dynamic registration (`dynamic_agent_client`, `agent_name_hint`, a per-Mac `ext_agent_host_id`) and persist the issued client ID, with no build-time client ID. Verify with `ChatGPTAccountSessionTests` asserting the authorize URL parameters for a first sign-in and for a sign-in that reuses a saved client ID.

## 2. Account-based provider support

- [x] 2.1 Add `AIProviderBilling.connectedAccount` and connection state in `AIProviderController`, so configured means signed in for these providers. Skip this task if the Copilot change already landed it. Verify with `CloudAIProviderTests` plus new cases asserting that connected-account providers are selectable only when signed in, available, and allowed by gating.
- [x] 2.2 Extend `AIProvidersSettingsView` and `AIProviderConfigurationSheet` so ChatGPT appears as its own entry in "Add Provider…" and in the Providers table, separate from the unchanged OpenAI API-key provider. The sheet shows an Account section (Continue with ChatGPT, waiting state with Cancel, account email, disconnect) instead of an API key. Verify with an app build.

## 3. OAuth and token session

- [x] 3.1 Implement the PKCE authorization flow with a one-shot `127.0.0.1` loopback listener, reusing `GitProviderPKCE` and the `GitProviderOAuthCallback` state and error parsing. Include a state check, ID-token claim checks (`iss`, `aud`, `exp`, `nonce`), and granted-scope verification. Verify with `ChatGPTAccountSessionTests` covering state mismatch, denied consent, and a missing plan-usage scope.
- [x] 3.2 Add `actor ChatGPTAccountSession` for Keychain storage of the token set and registration, proactive refresh with a single in-flight refresh that saves the rotated refresh token, and clearing on refresh rejection. Verify with `ChatGPTAccountSessionTests` using an in-memory Keychain store: concurrent requests share one refresh, a rejected refresh leaves no stale token, and nothing is written to `UserDefaults`.

## 4. ChatGPT provider

- [x] 4.1 Extract the OpenAI request, streaming, and agent-turn handling from `OpenAICommitMessageProvider` into a shared transport parameterized by endpoint, credential source, error mapping, and a streaming-required mode, with no behavior change for the API-key provider. Verify that the existing `CloudAIProviderTests` OpenAI cases still pass unchanged.
- [x] 4.2 Add `ChatGPTSubscriptionProvider` (`AIProviderID.chatGPTSubscription`, `.connectedAccount`, `requiresProToConfigureAPIKey = true`, `supportsRepositoryAgent = true`) using the shared transport in streaming-required mode with session tokens, and register it in `AIProviderRegistry.live`. Add a model list from `GET /v1/models`. Verify with `ChatGPTSubscriptionProviderTests`: tokens only appear in the authorization header and never in the request body, requests send `stream: true` and `store: false`, and agent turns decode from the SSE body.
- [x] 4.3 Map `subscription_sharing_usage_limit_exceeded`, `subscription_sharing_user_not_eligible`, `subscription_sharing_invalid_user`, and terminal refresh errors to `CommitMessageGenerationError` and availability states with no fallback to another provider. Verify with error-mapping cases in `ChatGPTSubscriptionProviderTests`.
- [x] 4.4 Enforce Pro gating for configuration and selection, while still allowing disconnect after Pro lapses. Verify with `CommitPlusAISelectionPolicyTests` cases for a Free user, a lapsed Pro user, and the policy-unavailable fallback.
- [x] 4.5 Implement disconnect: confirmation, best-effort refresh-token revocation, Keychain deletion, and fallback of the default provider to Apple Intelligence. Verify with a `CloudAIProviderTests` case.

## 5. Integration checks

- [x] 5.1 Run `xcodebuild … -only-testing:macgitTests/CloudAIProviderTests -only-testing:macgitTests/CommitPlusAISelectionPolicyTests -only-testing:macgitTests/ChatGPTAccountSessionTests -only-testing:macgitTests/ChatGPTSubscriptionProviderTests test` and verify that all pass.
- [ ] 5.2 Manual UI review in Settings → AI:
  - As a Free user, check the Pro prompt.
  - As Pro, sign in with a Plus account, cancel a pending sign-in, and check the connected layout.
  - Generate a commit message, run a repository agent mutation and confirm its prompt, and disconnect while ChatGPT is the default.
  - Verify by recording the results in the PR description.
- [ ] 5.3 Confirm no ChatGPT token appears in logs or the encoded `CloudSettingsDocument`. Verify by inspecting debug logs and the encoded document after a full sign-in and request.
