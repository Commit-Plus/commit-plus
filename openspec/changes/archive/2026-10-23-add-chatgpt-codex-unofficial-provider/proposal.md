# Proposal

## Why

The official "Sign in with ChatGPT" provider (`add-chatgpt-subscription-provider`) only works for ChatGPT plans that include usage in other apps. OpenAI blocks other plans on its consent screen with "A required permission is unavailable… with this workspace and plan", so ChatGPT Free users cannot connect. Other Mac apps, for example TablePro (PR #1618), sign in through the Codex CLI's OAuth client instead. That path uses the account's Codex allowance, which ChatGPT Free also includes. Commit+ users have asked for the same reach.

## What Changes

- Add a separate **ChatGPT (Codex) — Unofficial** provider to Settings → AI → "Add Provider…". The existing **OpenAI** (API key) and **ChatGPT** (official sign-in) providers stay unchanged.
- Sign in through the browser with the Codex CLI's public OAuth client and a loopback callback. The sheet shows the sign-in link with Copy Link, like the official provider.
- Send commit-message generation, repository chat, the repository agent, and conflict resolution to ChatGPT's Codex backend. Requests are billed to the account's Codex usage, never to API billing.
- Label the provider as unofficial everywhere it is configured. Before the first sign-in, the user must acknowledge that the interface:
  - is not supported by OpenAI,
  - may stop working at any time, and
  - is used at the user's own risk under OpenAI's terms.
- Show the signed-in email and the ChatGPT plan type read from the ID token, for example "free" or "plus".
- Disconnect revokes the refresh token and deletes the local tokens.
- Gated like the official ChatGPT provider: Commit+ Pro (`aiBringYourOwnKey`) is required to connect and use it, and a lapsed subscriber can still disconnect.
- A remote kill switch is out of scope. If OpenAI blocks the client, the provider becomes unavailable with a clear message. Nothing falls back silently.
- Importing an existing Codex CLI login (`~/.codex/auth.json`) is out of scope. Refresh tokens rotate, so sharing one with the Codex CLI would sign one of the two apps out.

## Capabilities

### New Capabilities
- `chatgpt-codex-provider`: Connecting a ChatGPT account through the unofficial Codex sign-in. It covers:
  - the risk acknowledgment, sign-in, and disconnect,
  - which AI features it serves,
  - availability and error reporting, and
  - how it is kept separate from the official ChatGPT and OpenAI providers.

### Modified Capabilities
<!-- None: no archived spec covers personal AI providers. The official ChatGPT provider is still an in-flight change. -->

## Impact

- **Code:**
  - A new provider and session in `macgit/Services/`, registered in `AIProviderRegistry`. They reuse `OpenAIResponsesClient` (streaming-required mode, plus Codex request headers and dialect fixes) and `ChatGPTLoopbackCallbackServer`.
  - Sign-in, acknowledgment, and plan UI in `AIProviderConfigurationSheet` and `AIProvidersSettingsView`, coordinated by `AIProviderController`.
- **Dependency on another change:** this builds on code from `add-chatgpt-subscription-provider`, so that change must land first.
- **External:**
  - The Codex CLI's public client ID and `chatgpt.com/backend-api/codex`, neither documented by OpenAI.
  - Requests identify as the Codex CLI (`originator`, `User-Agent`).
  - OpenAI's terms may not permit this use. The product decision to ship it rests with the maintainer.
- **Firebase:** none. Tokens stay in this Mac's Keychain and no synced settings fields change.
