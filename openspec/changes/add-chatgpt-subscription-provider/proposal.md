# Proposal

## Why

ChatGPT Plus and Pro subscribers already pay for model usage, but Commit+ can only use OpenAI through a separately billed API key. OpenAI now offers an official "Sign in with ChatGPT" OAuth flow that lets third-party apps draw on a subscriber's plan allowance, and open-source apps such as Commit+ can self-register for it.

## What Changes

- Add **ChatGPT** as an AI provider in Settings → AI, separate from the existing API-key OpenAI provider. It appears in the "Add Provider…" menu and, once connected, in the Providers table and the default-provider picker.
- Sign in through OpenAI's official "Sign in with ChatGPT" OAuth flow (open-source dynamic registration, loopback redirect) in the user's browser. The app checks that the plan-usage scope was actually granted before using the connection.
- Store ChatGPT tokens in this Mac's Keychain, refresh them automatically, and let the user disconnect from Settings. Tokens never reach model context, logs, or synced settings.
- Use the connection for the AI features the OpenAI provider already powers: commit-message generation, repository chat, the repository agent, and conflict resolution.
- Report plan-limit states (weekly cap reached, grant revoked or capped in ChatGPT settings, plan not eligible) as provider unavailability with an actionable message. The app never falls back to API billing.
- Require Commit+ Pro, using the existing `aiBringYourOwnKey` feature key.
- Out of scope: importing credentials from the Codex CLI, or any unofficial Codex endpoint.

## Capabilities

### New Capabilities
- `chatgpt-subscription-provider`: Connecting a ChatGPT subscription as an AI provider through official OAuth, its token storage and refresh, plan-limit reporting, Pro gating, and which AI features it serves.

### Modified Capabilities
<!-- None: no existing spec covers AI provider configuration. -->

## Impact

- **Code:**
  - A new provider in `macgit/Services/`, registered in `AIProviderRegistry`. It reuses the OpenAI request shape from `OpenAICommitMessageProvider` where the plan-usage API matches.
  - A new account-based billing kind on `AIProviderDescriptor`, shared with the GitHub Copilot change.
  - An OAuth PKCE flow with a `127.0.0.1` loopback redirect and dynamic client registration, and Keychain token storage next to `AIProviderCredentialStore`.
  - A streaming-required mode in the shared OpenAI Responses transport, because plan-usage requests must stream.
  - Sign-in UI in `AIProvidersSettingsView` and `AIProviderConfigurationSheet`.
- **External setup:** none. Open-source apps register dynamically on the user's first sign-in, so no client ID or secret ships in the app.
- **Plan gating:** `FeatureAccessResolver` with the `aiBringYourOwnKey` feature. The local policy fallback already covers this key.
- **Firebase:** none. No synced fields or feature-policy changes, because the gate reuses an existing feature key.
