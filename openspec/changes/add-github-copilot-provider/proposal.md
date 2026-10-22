# Proposal

## Why

Many Commit+ users already have GitHub Copilot, including the free Copilot tier, but today they must buy a separate API key to use AI features. Letting them sign in with GitHub and use their existing Copilot access removes that cost and makes AI features available to more Free-plan users.

## What Changes

- Add **GitHub Copilot** as an AI provider in Settings → AI. It appears in the "Add Provider…" menu and, once connected, in the Providers table and the default-provider picker.
- Connect through GitHub's official Copilot Language Server rather than an API key: the user signs in with a GitHub device code shown in the app, and the app never handles a raw Copilot token.
- Support both Copilot Free and paid Copilot plans. Model choices come from what the signed-in account is entitled to; a quota or entitlement error is shown as provider unavailability, not a crash.
- Use Copilot for the AI features other providers already power: commit-message generation, repository chat, and conflict resolution. Repository agent tool use is out of scope for the first version.
- Available on the Commit+ Free plan (no Pro gate).
- Let the user sign out of Copilot and remove the provider from Settings.
- Download or locate the Copilot Language Server at runtime instead of bundling a Node runtime in the app.

## Capabilities

### New Capabilities
- `github-copilot-provider`: Connecting a GitHub Copilot account as an AI provider, its sign-in and sign-out flow, model selection, availability reporting, and which AI features it serves.

### Modified Capabilities
<!-- None: no existing spec covers AI provider configuration. -->

## Impact

- **Code:** new provider in `macgit/Services/` registered in `AIProviderRegistry`; a new account-based billing kind on `AIProviderDescriptor`; sign-in and model UI in the Settings → AI providers table and configuration sheet (`AIProvidersSettingsView`, `AIProviderConfigurationSheet`); a runtime manager for the language server modeled on `GitRuntimeManager`.
- **Dependencies:** GitHub's `@github/copilot-language-server` distribution, fetched at runtime; GitHub Copilot terms of service apply to users.
- **Network:** traffic to GitHub sign-in and Copilot endpoints happens inside the language server process.
- **Firebase:** none. No synced settings fields, Firestore paths, or feature-policy changes; Copilot sign-in state stays on this Mac.
