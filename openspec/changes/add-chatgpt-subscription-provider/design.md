# Design

## Context

`OpenAICommitMessageProvider` already calls OpenAI's Responses API with an API key read from `AIProviderCredentialStore` (Keychain). It supports streaming and the repository agent. `AIProviderController` owns selection, availability, configuration, and Pro gating (`requiresProToConfigureAPIKey` checked against the `aiBringYourOwnKey` decision). Settings → AI uses `AIProvidersSettingsView` and `AIProviderConfigurationSheet`.

OpenAI's "Sign in with ChatGPT" program issues OAuth tokens that draw on a Plus/Pro subscriber's plan allowance once the plan-usage scope is granted. Open-source apps can self-register a client. The app already has OAuth PKCE helpers for Git providers (`GitProviderOAuthSession`, `GitProviderOAuthCallback`) and handles `macgit://` callbacks for GitLab.

The GitHub Copilot change (`add-github-copilot-provider`) introduces the same account-based provider support in Settings. Whichever change lands first adds it; the other reuses it.

## Goals / Non-Goals

**Goals:**
- A ChatGPT provider that uses only OpenAI's documented "Sign in with ChatGPT" flow.
- Reuse the OpenAI request and response handling, so features and agent support match the API-key provider.

**Non-Goals:**
- Importing tokens from the Codex CLI (`~/.codex/auth.json`), or calling `chatgpt.com/backend-api/codex/...` or any other unofficial endpoint.
- Merging ChatGPT into the existing OpenAI provider row. They stay separate providers because billing, gating, and failure modes differ.
- Showing the plan's remaining allowance. The app only reports cap or revocation errors in this version.

## Decisions

### Verified program facts (task 1.1, checked 2026-10-22)
Sources: developers.openai.com/siwc/token-sharing-open-source (sign-in, token-reference, models-and-inference, errors-and-recovery, profiles-and-sessions), /siwc/quickstart, and the cookbook article "Integrating Sign in with ChatGPT in your Opensource App". Not yet read: /siwc/request-client-id, /siwc/ui-ux-guidelines, and /preview-limitations.
- **Endpoints:**
  - Authorize: `https://auth.openai.com/api/accounts/authorize`.
  - Token and refresh: `https://auth.openai.com/api/accounts/oauth/token` (form-encoded).
  - Refresh uses `grant_type=refresh_token`, the issued `client_id`, `refresh_token`, and `resource`. It omits `scope`.
  - Revocation: the `revocation_endpoint` from `https://auth.openai.com/.well-known/openid-configuration`, called with `token`, `token_type_hint=refresh_token`, and `client_id`.
  - No userinfo endpoint is documented.
- **Client registration is dynamic, not a build setting:**
  - The first sign-in sends `client_id=dynamic_agent_client`, `agent_name_hint=Commit+`, and a stable per-host `ext_agent_host_id` (`urn:uuid:` or an RFC 9278 JWK thumbprint).
  - The callback returns the issued client ID (`oaiapp_…`), which is saved per account and used for the token exchange, refresh, revocation, and later sign-ins.
  - There is no client secret and no partner API key.
- **Scopes:** `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, with `resource=https://api.openai.com/v1`.
  - The token response returns a space-separated `scope`, and `chatgpt.tokens.use.direct` gates plan usage.
  - The authorize request also carries `state` and `nonce`. The ID token is validated against the JWKS for `iss`, `aud` (the issued client ID), `exp`, and `nonce`.
- **Redirect:** only HTTP loopback `http://127.0.0.1:<port>/auth/callback`.
  - Any available port works, but the path must match exactly, and `localhost` is not accepted.
  - The same URI is sent to both authorize and the code exchange.
  - Custom URL schemes are not documented.
- **Inference:**
  - Calls go to `POST https://api.openai.com/v1/responses` with `Authorization: Bearer <access token>`.
  - Every request must send `"store": false` and `"stream": true`. Only `response.completed` counts as success; `response.failed`, `response.incomplete`, and interrupted streams are failures.
  - Models come from `GET https://api.openai.com/v1/models` with the same token. The response is a `models` array: keep entries with `visibility == "list"` and use `slug` as the model.
- **Errors:**
  - Plan usage:
    - `subscription_sharing_usage_limit_exceeded` (429) is cap reached. It covers both the plan limit and the per-app limit; there is no separate weekly-cap code. Link `https://chatgpt.com/settings/usage`.
    - `subscription_sharing_user_not_eligible` (403) is an ineligible plan.
    - `subscription_sharing_invalid_user` (401) means sign in again.
    - `subscription_sharing_usage_unavailable` and `subscription_sharing_user_unavailable` (503) are transient.
    - `subscription_sharing_unsupported_capability` (400) means an unsupported input or tool.
  - OAuth:
    - Callback `error=access_denied` is a denied consent.
    - Refresh `invalid_grant`, `invalid_refresh_token`, `token_expired`, `refresh_token_*` mean clear the tokens and sign in again.
  - A revoked grant has no dedicated code and no notification. It appears as a refresh failure or `invalid_user`.
- **Tokens and identity:**
  - The access token lasts 3600 s. The refresh token lasts 30 days and rotates on every refresh, so refreshes must be serialized and the newest one stored.
  - Email comes from the validated ID token. The plan type is not documented.
- **Branding:** the button label is "Continue with ChatGPT".

### Separate provider sharing the OpenAI transport
Add `ChatGPTSubscriptionProvider` (in `macgit/Services/`), registered in `AIProviderRegistry.live` after `OpenAICommitMessageProvider`. Request building, SSE parsing, and agent turns move into a shared helper used by both, injected with a credential source.
- **Credential sources:** the API-key provider keeps reading `AIProviderCredentialStore`. The ChatGPT provider asks a token manager for a fresh access token on every request.
- **Rejected alternative:** a second credential mode inside `OpenAICommitMessageProvider`. That would mix two billing models, two gates, and two error vocabularies in one type.

### Token manager owned by the controller layer
An `actor ChatGPTAccountSession` stores access and refresh tokens and their expiry as one Keychain item, using the same service family as `KeychainAIProviderCredentialStore`.
- **Refresh:** proactive within a short window before expiry, with a single in-flight refresh shared by concurrent requests. Refresh tokens rotate, so the newest one is saved after each refresh.
- **Rejected refresh token:** clears the item, which makes the provider report "Sign in required".
- **Ownership:** `AIProviderController` owns the session instance and exposes its connection state for Settings. No new controller is added.

### OAuth flow
Reuse the PKCE helpers (`GitProviderPKCE`) and the callback parsing in `GitProviderOAuthCallback` (state check, provider error), generalized so it doesn't need a Git provider session.
- **Redirect URI:** OpenAI accepts only HTTP loopback. The app starts a one-shot listener on `127.0.0.1`, preferring port 1455 and otherwise any free port. It sends the same `http://127.0.0.1:<port>/auth/callback` to authorize and to the code exchange. The app is not sandboxed, so this needs no new entitlement.
- **Dynamic registration:** there is no client ID in build configuration.
  - The first sign-in uses `dynamic_agent_client` with `agent_name_hint=Commit+` and a per-Mac `ext_agent_host_id` (`urn:uuid:`).
  - The callback's issued `client_id` is used for the token exchange and refresh, and saved for later sign-ins.
  - The issued client ID and the host ID are kept in the Keychain registration item, which survives disconnect.
  - An issued client ID is bound to the account and workspace that registered it. Another account gets `3p_login_workspace_scope_denied`. The sheet therefore offers "Use Another Account", which registers again through `dynamic_agent_client` and replaces the saved registration only after that sign-in succeeds. A returning sign-in rejects a callback whose `client_id` differs from the saved one.
- **Sign-in wait:** while the browser is open, the sheet shows the authorization link with a Copy Link button for opening it in another browser profile. The listener closes on success, failure, Cancel, sheet dismissal, or after a 10-minute timeout.
- **Scopes:** `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` with `resource=https://api.openai.com/v1`. After the code exchange, the app requires `chatgpt.tokens.use.direct` in the granted `scope`; without it, no tokens are saved.
- **ID token:** the app checks `iss`, `aud` (the issued client ID), `exp`, and `nonce`, and reads `email` and `sub`. The token comes directly from the token endpoint over TLS, which OIDC Core §3.1.3.7 accepts in place of a JWKS signature check.
- **Configuration:** endpoints, scopes, resource, and the agent name live in one `ChatGPTAuthConfiguration` type.

### Streaming-required transport
OpenAI requires `"stream": true` and `"store": false` on every plan-usage request. The shared Responses transport has a streaming-required mode:
- One-shot calls (commit message, structured repository answer, agent turn, conflict plan) send `stream: true` and read the whole SSE body. They decode the `response` object from `response.completed`, or from `response.incomplete`, with the existing response parsing.
- `response.failed` goes through the same error mapping as HTTP errors.
- Live repository chat uses the existing incremental SSE path.
The API-key OpenAI provider keeps its current non-streaming requests.

### Gating
The descriptor sets `requiresProToConfigureAPIKey = true`, so the existing `aiBringYourOwnKey` decision gates both configuration and selection, and the local `proOnlyRule` covers the policy-unavailable case. A user who loses Pro can still disconnect, matching how existing Pro API keys behave.

### Error mapping
| OpenAI response | Result |
| --- | --- |
| `subscription_sharing_usage_limit_exceeded` (429) | New `CommitMessageGenerationError` case. The provider is unavailable with a "plan limit reached" message for a 15-minute cooldown, which links to `chatgpt.com/settings/usage`. |
| `subscription_sharing_user_not_eligible` (403) | New error case. The provider stays unavailable until the next sign-in. |
| `subscription_sharing_invalid_user` (401), or a terminal refresh error (`invalid_grant`, `refresh_token_*`, …) | Tokens are cleared and the provider shows "Sign in required". |
| `*_unavailable` (503) and other codes | A request failure with OpenAI's message. |

There is no automatic retry or provider fallback.

### Settings UI and window scoping
ChatGPT is its own entry in "Add Provider…", next to OpenAI. The OpenAI API-key provider is unchanged.
- **Account section:** a "Continue with ChatGPT" button (OpenAI's required label) opens the browser. While pending, the sheet shows a waiting state with Cancel. When connected, it shows the account email (OpenAI does not expose the plan type) and a Disconnect button. A successful sign-in connects immediately; Save only applies the model.
- **Model section:** a model picker. When connected it is filled from `GET /v1/models` (`visibility == "list"`, `slug`), falling back to the built-in catalog. The default model is `gpt-6.1-sol`. Thinking uses the shared setting.

No new menu, toolbar, or notification commands are added. The callback arrives on the loopback listener started by the pending sign-in, which is matched by `state`, so only one sign-in can be pending at a time.

### Disconnect
Disconnecting asks for confirmation, then makes a best-effort call to revoke the refresh token at the discovery document's `revocation_endpoint`. It then deletes the token item from the Keychain and keeps the registration item. If ChatGPT was the default provider, the default reverts to Apple Intelligence.

## Risks / Trade-offs

- [The program's endpoints, scopes, or eligibility change] → Keep the scope names, endpoints, and client ID in one configuration type. Task 1 verifies them against OpenAI's live documentation before any implementation.
- [OpenAI only grants commercial registrations a trial] → Commit+ uses the open-source dynamic registration (AGPL), which needs no manual registration step.
- [The plan-usage API differs from the public Responses API] → The shared transport takes the endpoint and headers as parameters. If the shape diverges, the ChatGPT provider supplies its own request builder while sharing response parsing.
- [Another local process races for the loopback callback] → The PKCE verifier never leaves the app, the state check rejects unsolicited callbacks, and the listener closes after the first matching callback or on cancel.

## Migration Plan

This is additive. The existing OpenAI API-key provider and its stored key are unaffected. Rollback means removing the provider from the registry; a stale selection falls back to Apple Intelligence, and the Keychain item can be removed on the next launch.

## Open Questions

- Whether to show the plan's remaining allowance if OpenAI exposes it. This can be added later without changing the requirements.
