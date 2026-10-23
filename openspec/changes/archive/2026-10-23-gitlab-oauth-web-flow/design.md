# Design

## Context

See proposal.md for motivation. Current state after `github-oauth-web-flow`:

- `GitProviderAccountController` (app-wide, shared by all scenes) owns connections.
  - `connectGitLabDotCom()` and GitLab.com `reconnect(_:)` call `startGitLabDeviceAuthorization(host:)`.
  - `startGitLabOAuth(host:)` still exists from before July but has no caller. It builds a session with `redirectURI` `macgit://git-provider/oauth/callback` and opens the URL, with no expiry or waiting state.
  - `connectSelfHostedGitLab(hostURL:)` has no caller either; the UI connects self-hosted GitLab with a personal access token or SSH.
- The browser plumbing built for GitHub is provider-aware already:
  - `GitProviderOAuthSession` has a separate `appCallbackURL`, a `startedAt`, and `GitProviderOAuthCallback.parse` checks `state` before `error` and maps `access_denied`.
  - `handleProviderOAuthCallback(_:)` takes the session before any await, checks the 10-minute lifetime, and dispatches on `session.provider`; its `.gitlab` branch calls `GitLabProviderAuthService.exchangeCallback` and `fetchAccount`.
  - The Settings window and `ContentView` scenes route `macgit://git-provider` URLs to that method.
- The waiting state is GitHub-specific: `isAwaitingGitHubBrowserAuthorization`, `cancelGitHubAuthorization()`, `connectGitHubWithDeviceCode()`, and the sheet's `awaitsBrowserResult` / `useDeviceCode()` / `cancelConnection()` call those.
- `GitLabProviderAuthService` already implements `authorizationURL(for:)` (S256 challenge, `state`, scopes) and `exchangeCallback(_:session:)` (`grant_type=authorization_code`, `code_verifier`, `redirect_uri`, no secret). `refreshToken` sends `configuration.redirectURI` as `redirect_uri`.
- GitLab (Doorkeeper) requirements: the `redirect_uri` must exactly match a registered redirect URI; a non-confidential application can exchange codes with PKCE and no `client_secret`; denial returns `error=access_denied` with `state`. The device flow working today without a secret shows Commit+'s application is non-confidential.
- `../landing-page` (now on `release`) serves `/oauth/github/callback` from `lib/github-oauth.ts` (`appCallbackURL`, input validation) and `app/oauth/github/callback/route.ts` (HTML outside the layout, nonce CSP, no-store, no-referrer).

## Goals / Non-Goals

**Goals:**
- GitLab.com connects exactly like GitHub.com from the user's point of view.
- One provider-neutral browser-waiting state in the controller and sheet, rather than a GitLab copy of the GitHub one.

**Non-Goals:**
- Self-hosted GitLab OAuth (each instance would need its own application). The unused `connectSelfHostedGitLab` is left alone.
- Changing scopes, refresh handling, or the token vault.
- A commitplus.app token endpoint for GitLab.

## Decisions

### Same callback handoff as GitHub, separate path
GitLab redirects to `https://commitplus.app/oauth/gitlab/callback`. The page forwards to `macgit://git-provider/oauth/gitlab/callback`.
- In `../landing-page`, generalize `lib/github-oauth.ts` into a provider-keyed helper (`github`, `gitlab`, each with its redirect and app callback URL) and share the HTML renderer. The GitLab route is a thin `GET` like the GitHub one, with the same headers and CSP. GitLab codes (64 hex characters) and `state` (UUID) fit the existing validation.
- The page wording names the provider ("connect your GitLab account again").
- **Rejected alternative:** registering `macgit://git-provider/oauth/callback` directly with GitLab, which GitLab allows. It would skip a deployment, but users would get a different landing experience per provider and no "Open Commit+" fallback. The user asked for both providers to match.
- **Rejected alternative:** one shared `/oauth/callback` page for both providers. The page would have to infer the provider, and each provider's registered URL would be less specific.

### Direct exchange, no secret
The app keeps calling GitLab's `/oauth/token` itself through the existing `exchangeCallback`, with `redirect_uri` set to the HTTPS callback URL.
- **Rejected alternative:** a commitplus.app exchange route like GitHub's. It is only needed when the provider requires a secret, and it would add a public endpoint, rate limiting, and an outage point for no gain.

### Configuration
`GitLabProviderAuthConfiguration` gains an app callback URL:
- `redirectURI`: `https://commitplus.app/oauth/gitlab/callback`, sent to GitLab on authorize, token exchange, and refresh.
- `appCallbackURL`: `macgit://git-provider/oauth/gitlab/callback`, stored on the session.

Refresh sends `redirect_uri` today. Doorkeeper does not check it on `refresh_token` grants, but to be safe the old `macgit://git-provider/oauth/callback` stays registered on the GitLab application until a refresh with the new value is verified (see Migration Plan).

### Controller: one browser flow for both providers
`GitProviderAccountController` remains the owner; no new controller.
- `isAwaitingGitHubBrowserAuthorization` becomes `awaitingBrowserAuthorizationProvider: GitProviderKind?`, derived from `pendingOAuthSession` in its existing `didSet`. The expiry task and lifetime are unchanged.
- `startGitHubBrowserAuthorization()` becomes `startBrowserAuthorization(_ session:, authorizationURL:)` shared by both providers. The GitHub wrapper builds its session as today; `startGitLabBrowserAuthorization()` replaces `startGitLabOAuth(host:)` with a `.gitlabDotCom` session (UUID `state`, PKCE verifier, both URLs).
- `connectGitLabDotCom()` and GitLab.com `reconnect(_:)` call it after the existing limit checks.
- `cancelGitHubAuthorization()` becomes `cancelBrowserAuthorization()`, which clears any pending session. `connectGitLabWithDeviceCode()` mirrors `connectGitHubWithDeviceCode()`, calling `startGitLabDeviceAuthorization(host: .gitlabDotCom)`.
- `handleProviderOAuthCallback(_:)` needs no new branch. A callback for the other provider does not match the pending session's path, so it returns `false` and the pending session keeps waiting.
- No menu, toolbar, or notification commands are added. Callback routing stays app-wide, as for GitHub, since a connection belongs to the app, not to a repository window.

### UI
In `GitProviderAddAccountSheet`, the waiting pane, Cancel, and "Use a device code instead" are driven by `awaitingBrowserAuthorizationProvider` and shown for whichever provider the sheet started. `useDeviceCode()` calls the device fallback for the selected provider. The device-code view is reused unchanged.

## Risks / Trade-offs

- [The redirect URI is not registered, or the application is confidential] → GitLab shows an error page or the exchange fails with `invalid_client`. Mitigation: register and verify before the app ships; the device fallback still works.
- [Refresh rejects the new `redirect_uri`] → Browser-connected accounts would need reconnecting every 2 hours. Mitigation: keep the old URI registered, and include a refresh check in the manual review before release.
- [Renaming the GitHub waiting-state API breaks GitHub behavior] → The existing GitHub controller tests are updated to the new names and must still pass.
- [The code briefly sits in the callback page URL and a `macgit://` URL] → Useless without the PKCE verifier, which stays in the app's memory. Same page protections as GitHub.

## Migration Plan

1. In `../landing-page`: add the GitLab callback route, deploy to production, and check the page with sample values.
2. On Commit+'s GitLab.com application: add `https://commitplus.app/oauth/gitlab/callback` as a redirect URI, keep the existing `macgit://git-provider/oauth/callback`, and confirm "Confidential" is off and the scopes include `api`, `read_user`, and `write_repository`.
3. Ship the macgit change. Existing GitLab accounts and tokens are untouched.
4. After a release has verified refresh with the new redirect URI, the old `macgit://` redirect URI can be removed from the GitLab application.
5. Rollback: a build that calls the device flow, as today, needs no backend. The callback page can stay deployed unused.
