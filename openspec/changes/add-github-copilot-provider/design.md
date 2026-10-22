# Design

## Context

AI providers implement `CommitMessageAIProvider` and are listed in `AIProviderRegistry.live`. `AIProviderController` owns provider selection, availability, and configuration. Settings → AI (`AIProvidersSettingsView` and `AIProviderConfigurationSheet`) only lists providers whose `AIProviderDescriptor.billing` is `.bringYourOwnKey`, and treats "configured" as "has an API key in `AIProviderCredentialStore`".

Copilot does not fit the API-key model. GitHub's supported way for a third-party client to use Copilot is the Copilot Language Server (`@github/copilot-language-server`), which owns sign-in, token exchange, entitlement, and model access. The client talks to it over stdio using LSP/JSON-RPC. The app already runs external processes and manages a downloadable runtime for Git (`GitRuntimeManager`, `GitRuntimeManifest`) and Git LFS (`GitLFSRuntime`). It also already renders a GitHub device-code prompt (`GitProviderDeviceAuthorizationView`).

The ChatGPT subscription change (`add-chatgpt-subscription-provider`) needs the same account-based provider support in Settings. Whichever change lands first introduces it; the other reuses it.

## Goals / Non-Goals

**Goals:**
- A Copilot provider that uses only GitHub's supported client surface.
- An account-based provider kind in Settings → AI that both new providers share.
- No Copilot or GitHub token handled, stored, or logged by Commit+ itself.

**Non-Goals:**
- Inline code completion, or any editor feature beyond the existing AI features.
- Repository agent tool calling through Copilot (first version).
- Reusing the GitHub Git-provider connection from Settings → Connections for Copilot. Those tokens belong to Commit+'s own GitHub OAuth app and do not grant Copilot access.
- Bundling Node.js or the language server in the app bundle.

## Decisions

### Talk to the official Copilot Language Server instead of private HTTP endpoints
The provider launches the language server and drives it over stdio JSON-RPC: sign-in initiate/confirm/status, sign-out, the models listing, and the conversation/chat requests.
- **Rejected alternative:** calling Copilot's chat endpoint directly with a GitHub token exchanged at the `copilot_internal` token endpoint. That requires borrowing another product's OAuth client ID and depends on undocumented endpoints. It risks violating GitHub's terms and breaking without notice.

### Manage the server like the Git runtime
A new `CopilotLanguageServerRuntime` handles locating, downloading, verifying, and updating the server, modeled on `GitRuntimeManager`/`GitLFSRuntime`. It is not a new abstraction family; it follows the same manifest-plus-cache shape, stores files under Application Support, and pins a server version.
- **Rejected alternative:** bundling the npm package. That would ship a Node runtime and an npm tree inside the app and require an app release for every server update.
- **To resolve in task 1:** whether the distribution provides a standalone macOS executable. If it requires Node, the runtime manager uses a Node binary from a pinned download instead.

### Process lifecycle owned by an actor
An `actor CopilotLanguageServerClient` owns the server process, the JSON-RPC framing, and request correlation. Like `GitStatusService`, it starts the server lazily on first use and restarts it once after an unexpected exit. All `Process()` work stays off the main actor. The provider type (`GitHubCopilotProvider`, in `macgit/Services/`) adapts `CommitMessageAIProvider` calls onto this client. `AIProviderController` remains the owner of selection and availability; no parallel controller is added.

### Account-based billing kind
`AIProviderBilling` gains `.connectedAccount`. `AIProviderController` exposes connection state for these providers, so "configured" means "signed in" rather than "has an API key".
- **Settings → AI:** includes these providers in the Providers table and the "Add Provider…" menu.
- **`AIProviderConfigurationSheet`:** renders an Account section with sign-in, the device code, and sign-out instead of the API key field.
- **Gating:** `requiresProToConfigureAPIKey` stays `false` for Copilot, so no `FeatureAccessResolver` gate applies, per the proposal.

### Prompting
Copilot gets the existing prompt builders (commit message, repository chat, conflict resolution) as single-turn conversations. `supportsRepositoryAgent` is `false`, so agent features use the app's existing "provider does not support the agent" path. `inputCharacterBudget` is set conservatively, because Copilot model context differs by plan.

### Window scoping
No new menu, toolbar, or notification commands are added. Sign-in runs inside the Settings window's sheet. "Configure AI…" from `AIProviderMenu` keeps posting `.showAppSettings` with the AI section, which `AppSettingsView` already handles.

## Risks / Trade-offs

- [Language server protocol for chat is less documented than completions] → Task 1 is a spike that confirms the sign-in, models, and conversation methods against a pinned server version before any UI work. The app pins the version so protocol drift needs an explicit update.
- [Server download fails or is blocked by a proxy] → Report it as provider unavailability with a Retry action. Other providers keep working.
- [Copilot Free quota is small] → Show quota errors clearly. Never retry automatically in a loop.
- [Telemetry defaults of the language server] → Expose the server's telemetry setting in the configuration sheet, defaulting to the server's own default. Mention it in the sheet footer.
- [Process leaks on app quit] → Terminate the server from the actor when the app terminates, and on sign-out when it is idle.

## Migration Plan

This is additive. Existing API-key providers and stored keys are untouched. Rollback means removing the provider from the registry; a stale `selectedProviderID` of `github-copilot` already falls back to Apple Intelligence through the existing unknown-ID handling in `AIProviderController`.

## Open Questions

- The exact server version to pin, and whether to auto-update within a minor range. This can be decided at implementation time without changing behavior.
