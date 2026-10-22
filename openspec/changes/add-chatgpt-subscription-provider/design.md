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

### Separate provider sharing the OpenAI transport
Add `ChatGPTSubscriptionProvider` (in `macgit/Services/`), registered in `AIProviderRegistry.live` after `OpenAICommitMessageProvider`. Request building, SSE parsing, and agent turns move into a shared helper used by both, injected with a credential source.
- **Credential sources:** the API-key provider keeps reading `AIProviderCredentialStore`. The ChatGPT provider asks a token manager for a fresh access token on every request.
- **Rejected alternative:** a second credential mode inside `OpenAICommitMessageProvider`. That would mix two billing models, two gates, and two error vocabularies in one type.

### Token manager owned by the controller layer
An `actor ChatGPTAccountSession` stores access and refresh tokens and their expiry as one Keychain item, using the same service family as `KeychainAIProviderCredentialStore`.
- **Refresh:** proactive within a short window before expiry, with a single in-flight refresh shared by concurrent requests.
- **Rejected refresh token:** clears the item, which makes the provider report "Sign in required".
- **Ownership:** `AIProviderController` owns the session instance and exposes its connection state for Settings. No new controller is added.

### OAuth flow
Reuse the PKCE helpers (S256 verifier and challenge, random state) and the existing external-event callback path.
- **Redirect URI:** whichever OpenAI accepts for this client type, decided in task 1. Prefer a `macgit://` callback handled like the GitLab flow. Fall back to an ephemeral loopback listener only if custom schemes are not accepted.
- **Scopes:** the app requests the documented plan-usage scopes with the API resource indicator. After the token exchange it verifies the granted scopes before saving.
- **Client ID:** comes from build configuration (`Info.plist` key filled from a build setting, like `GitHubProviderAuthConfiguration.appConfiguration()`). With no client ID configured, ChatGPT is listed but shows "Not configured in this build".

### Gating
The descriptor sets `requiresProToConfigureAPIKey = true`, so the existing `aiBringYourOwnKey` decision gates both configuration and selection, and the local `proOnlyRule` covers the policy-unavailable case. A user who loses Pro can still disconnect, matching how existing Pro API keys behave.

### Error mapping
Plan-cap, revoked-grant, and ineligible-plan responses map to new `CommitMessageGenerationError` cases with user-facing messages. They mark the provider unavailable through the existing availability refresh. There is no automatic retry or provider fallback.

### Settings UI and window scoping
Uses the account-based provider kind:
- **Account section:** "Sign in with ChatGPT" opens the browser. While pending, the sheet shows a waiting state with Cancel. When connected, it shows the account and plan.
- **Model section:** a model picker with the default model, plus a reasoning-effort picker where the model supports it.

No new menu, toolbar, or notification commands are added. The OAuth callback is matched to the pending session by `state`, not by window, because only one sign-in can be pending at a time.

## Risks / Trade-offs

- [The program's endpoints, scopes, or eligibility change] → Keep the scope names, endpoints, and client ID in one configuration type. Task 1 verifies them against OpenAI's live documentation before any implementation.
- [OpenAI only grants commercial registrations a trial] → Commit+ registers as an open-source app (AGPL). Track the registration status in the rollout tasks.
- [The plan-usage API differs from the public Responses API] → The shared transport takes the endpoint and headers as parameters. If the shape diverges, the ChatGPT provider supplies its own request builder while sharing response parsing.
- [Callback hijacking by another app registering `macgit://`] → The PKCE verifier never leaves the app, and the state check rejects unsolicited callbacks.

## Migration Plan

This is additive. The existing OpenAI API-key provider and its stored key are unaffected. Rollback means removing the provider from the registry; a stale selection falls back to Apple Intelligence, and the Keychain item can be removed on the next launch.

## Open Questions

- Whether to show the plan's remaining allowance if OpenAI exposes it. This can be added later without changing the requirements.
