# Design

## Context

This change builds on `add-chatgpt-subscription-provider`, which is implemented on `codex/chatgpt-subscription-provider` but not yet archived. That change already provides most of the parts this one needs:

| Existing part | What it does |
|---|---|
| `OpenAIResponsesClient` | Responses transport with a streaming-required mode, which buffers the SSE body and decodes the final response |
| `ChatGPTLoopbackCallbackServer` | One-shot listener on `127.0.0.1` |
| `ChatGPTAccountSession` | Actor with PKCE, a Keychain store, and single-flight refresh |
| `.connectedAccount` | Billing kind on `AIProviderDescriptor` |
| `AIProviderController` | Coordinates ChatGPT sign-in and disconnect, including the timeout and authorization link state |
| `AIProviderConfigurationSheet` | The connected-account section of the sheet |

The Codex flow is reverse-engineered from the Codex CLI. TablePro PR #1618 (merged 2026-06-08, `apple/TablePro/Core/AI/ChatGPTCodex/`) is the reference implementation. None of the values below are documented by OpenAI.

| Item | Value |
|---|---|
| Client ID | `app_EMoamEEZ73f0CkXaXp7hrann` (Codex CLI) |
| Authorize | `https://auth.openai.com/oauth/authorize` with `response_type=code`, PKCE S256, `state`, `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator=codex_cli_rs` |
| Scope | `openid profile email offline_access api.connectors.read api.connectors.invoke` |
| Redirect | `http://localhost:1455/auth/callback` (fixed port, `localhost` host) |
| Token / revoke | `https://auth.openai.com/oauth/token` and `/oauth/revoke`, form-encoded; refresh sends `scope` |
| Inference | `POST https://chatgpt.com/backend-api/codex/responses`, `stream` and `store:false` |
| Headers | `Authorization: Bearer`, `ChatGPT-Account-ID`, `session-id`, `originator: codex_cli_rs`, `User-Agent: codex_cli_rs/<version>` |
| Claims | ID token `https://api.openai.com/auth` → `chatgpt_account_id`, `chatgpt_plan_type`; email from `https://api.openai.com/profile` or `email` |

TablePro also reports three ways the Codex backend's dialect differs from the public API:
- It rejects `max_output_tokens`.
- Reasoning items need a `summary`.
- Tool-call arguments may be keyed by `item_id`, so the arguments are recovered from `response.output_item.done`.

Rechecked on 2026-10-23 against TablePro `main` (`apple/TablePro/Core/AI/ChatGPTCodex/`) and Codex CLI `main` (`codex-rs/login`, `codex-rs/codex-api`):
- The client ID, endpoints, scope, port, redirect, headers, and claims above match both sources.
- The Codex CLI also sends `codex_cli_simplified_flow=true` on authorize; this app sends it too.
- The Codex CLI sends refresh and revoke as JSON, while TablePro sends them form-encoded with `scope` on refresh. This app keeps the form encoding that `ChatGPTAccountSession` already uses, as TablePro does.
- TablePro omits `max_output_tokens` and sends `reasoning: {effort, summary: "auto"}`. It builds tool calls from `response.output_item.done` items instead of the final `response.completed` output.

Backend error signals from the Codex CLI source (`api_bridge.rs`, `sse/responses_error.rs`, `auth/manager.rs`):
- HTTP 429 carries the cause in `error.type`, not `error.code`: `usage_limit_reached` is the Codex usage limit, and `usage_not_included` means the plan does not include Codex.
- A `response.failed` stream event carries `error.code`: `usage_not_included`, `rate_limit_exceeded`, `insufficient_quota`, or `context_length_exceeded`.
- A refresh is permanent (sign in again) on HTTP 401, on 400 `invalid_grant`, or on `refresh_token_expired`, `refresh_token_reused`, or `refresh_token_invalidated`.

## Goals / Non-Goals

**Goals:**
- Reuse the official ChatGPT provider's transport, listener, session pattern, controller flow, and sheet section. Do not add parallel copies.
- Keep the Codex tokens, settings, and errors fully separate from the official ChatGPT provider.
- Make the unofficial status impossible to miss.

**Non-Goals:**
- Importing `~/.codex/auth.json`, because a shared rotating refresh token would sign one app out.
- A remote kill switch or a feature-policy flag. This would need a Firebase change; it can be revisited if OpenAI starts blocking.
- Model discovery from the backend. The provider uses a curated model list with "Other…".
- Multiple saved Codex accounts. One account at a time; signing in again replaces it.

## Decisions

### Generalize the session instead of copying it
`ChatGPTAccountSession` becomes parameterized by a flow descriptor, so that one actor drives both flows. The descriptor holds:
- the authorize URL builder,
- the token and revoke endpoints,
- the redirect host and port,
- whether the flow uses dynamic registration,
- the claim extraction, and
- the Keychain account names.

Codex sessions use a fixed client ID with no registration, skip the `chatgpt.tokens.use.direct` scope check, and read the account ID and plan type from the ID token.

Alternative considered: a separate `ChatGPTCodexSession` copied from TablePro. Rejected because it would duplicate refresh, revocation, Keychain, and the state-checking logic that is already tested.

### ID token checks
Codex sends no `nonce`. The app checks `iss`, `aud` (the Codex client ID), and `exp`, and requires a non-empty `chatgpt_account_id`. This matches what the Codex CLI relies on: the token comes straight from the token endpoint over TLS.

### Loopback listener
The listener reuses `ChatGPTLoopbackCallbackServer` with a required port of 1455 (no fallback, because the Codex client allows only that port) and a `localhost` redirect URI. It still binds to `127.0.0.1`. If port 1455 is in use (for example, by the Codex CLI's own login), sign-in fails with "Port 1455 is in use. Close other ChatGPT sign-ins and try again."

### Transport
`OpenAIResponsesClient` gains a `.codexBackend` dialect. This dialect:
- adds the Codex headers, with a per-provider-instance `session-id` UUID and the account ID read from the session;
- omits `max_output_tokens`;
- adds `summary: "auto"` when reasoning is set; and
- takes final tool-call arguments from `response.output_item.done`.

The `.standard` and `.streamingRequired` behavior must not change; existing OpenAI and ChatGPT tests guard this.

### Provider and descriptor
`ChatGPTCodexProvider` mirrors `ChatGPTSubscriptionProvider`:
- id `chatgpt-codex`, display name "ChatGPT (Codex)", billing `.connectedAccount`, `requiresProToConfigureAPIKey: true`;
- supports the repository agent;
- curated models `gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-5.5`, with the default `gpt-5.6-sol` (the same slugs TablePro uses), plus "Other…".

The descriptor gains `isUnofficial`. The provider list, menu, and sheet use it to show an "Unofficial" badge.

### Error mapping
| Signal | Result |
|---|---|
| 401, or a terminal refresh error | Sign out locally, then `codexSignInRequired` |
| 429, or type/code `usage_limit_reached` or `rate_limit_exceeded` | `codexUsageLimitReached`, provider unavailable for 15 minutes (the same cooldown as the official provider) |
| Type/code `usage_not_included` (429 or stream event) | `codexPlanNotAllowed` |
| `invalid_client` / `unauthorized_client` at authorize or token, or 403 without a known code | `codexClientRejected`: "The unofficial ChatGPT (Codex) connection is not working. OpenAI may have blocked it." |

No case falls back to another provider. The codes were confirmed against the Codex CLI source in task 1.1; any code not in the table is shown as `providerRequestFailed` with the backend message.

### Acknowledgment state
A local `UserDefaults` flag (`ai.chatgptCodex.riskAcknowledged`) records the acknowledgment. It is local per Mac and not added to `CloudSettingsDocument`, so there is no Firebase impact. Removing the provider does not clear it.

### Ownership and window scoping
`AIProviderController` owns the sign-in, timeout, Copy Link, disconnect, and model refresh, generalized from the ChatGPT methods to take the provider ID. The sheet stays presentational.

No menu, toolbar, or notification command is added. The provider menu already uses the window-scoped "Configure" notification.

## Risks / Trade-offs

- **OpenAI blocks the Codex client ID or changes the backend:** the provider becomes unavailable with `codexClientRejected`, and the official providers are unaffected. Fixing it needs an app update.
- **OpenAI's terms may forbid this use:** the explicit acknowledgment and the persistent "Unofficial" label address this. Whether to ship is the maintainer's decision.
- **Port 1455 conflicts with the Codex CLI's login:** the app shows a clear error, and the user retries after the CLI finishes.
- **Requests impersonate the Codex CLI** (`originator`, `User-Agent`): this is required by the backend. It is stated in the acknowledgment text rather than hidden.
- **Generalizing the session could regress the official provider:** the existing `ChatGPTAccountSessionTests` and `ChatGPTSubscriptionProviderTests` must pass unchanged.

## Migration Plan

Additive. There is no data migration, and rolling back removes the provider. Stored Codex tokens become orphaned Keychain items, deleted on the next disconnect or ignored.

## Open Questions

- None. The error codes were confirmed from the Codex CLI source (task 1.1); the manual review (task 5.2) checks them against real responses.
