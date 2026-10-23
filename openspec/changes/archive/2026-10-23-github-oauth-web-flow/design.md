# Design

## Context

See proposal.md for motivation. Current state:

- `GitProviderAccountController` (app-wide, one instance shared by all scenes) owns connecting accounts. `connectGitHub()` and `reconnect(_:)` call `startGitHubDeviceAuthorization()`. That method uses `GitHubProviderAuthService` with Commit+'s OAuth app client ID from `Info.plist` (`GitHubOAuthClientID`, fallback `Ov23lictC3FXsN0kjsbs`) and the scopes `repo read:user workflow`.
- Web-flow pieces already exist but no shipping path uses them:
  - `GitProviderOAuthSession` (state, PKCE verifier, redirect URI) and `GitProviderOAuthCallback.parse`, which checks scheme, host, port, path, and `state`.
  - `GitProviderPKCE` (S256).
  - `pendingOAuthSession` and `handleProviderOAuthCallback(_:)` in the controller, wired to GitLab's `macgit://git-provider/oauth/callback`.
  - `startGitLabOAuth` exists but has no caller.
- `macgit://` URLs reach the controller only through `ContentView.onOpenURL`, which serves the Welcome and repository windows. The Settings window (`Window("Settings", id: "settings")`), where accounts are connected, has no URL handler. The scenes' `handlesExternalEvents` lists cover `macgit://session` and `macgit://open-repository`, but not `macgit://git-provider`. Observed on 2026-10-23 with a Debug build: the scheme opens the running app in every case. When only Settings is open, a `macgit://git-provider/...` URL makes SwiftUI open the Welcome window in front of Settings. When Welcome is already open, no extra window appears. It was not confirmed whether Welcome's `onOpenURL` handler runs.
- The Commit+ web sign-in already hands off from commitplus.app to `macgit://session?state&token`. commitplus.app is the Next.js app in `../landing-page`, deployed on Vercel. It has server routes under `app/api` (for example `api/auth/app-token`) and mounts `@vercel/analytics` in the root layout.
- GitHub's OAuth web flow (confirmed in GitHub's "Authorizing OAuth apps" docs):
  - PKCE is supported with `S256` only.
  - The `client_secret` is required for the code exchange even with PKCE.
  - `state` is echoed back.
  - Codes expire after 10 minutes.
  - `redirect_uri` must share host and port with a registered callback URL, with its path under it.
  - An app may register several callback URLs.

## Goals / Non-Goals

**Goals:**
- One-click GitHub.com connection that returns to Commit+ on its own.
- No `client_secret` in the open-source app, and no access token in any URL or in the browser.
- Reuse the existing OAuth session, callback, and PKCE types and the existing controller. No parallel connection controller.

**Non-Goals:**
- Turning on GitLab's web flow (`startGitLabOAuth`), although the routing fix below also benefits it later.
- Changing scopes, token storage (`GitProviderTokenVault`), account identity, or plan limits.
- Expiring GitHub user tokens or refresh handling. Commit+'s OAuth app issues non-expiring tokens today; this change keeps that.

## Decisions

### Callback page forwards; it never exchanges
GitHub redirects to `https://commitplus.app/oauth/github/callback`. That page builds `macgit://git-provider/oauth/github/callback?code=…&state=…`, or `?error=…&state=…` on denial, and calls `location.replace` with it. It then removes the query from its own URL (`history.replaceState`) and shows an "Open Commit+" button holding the same link.
- The page sets `Referrer-Policy: no-referrer` and `Cache-Control: no-store`.
- It is excluded from Vercel Analytics (route outside the analytics layout, or a `beforeSend` that drops it), so the code is never sent to analytics.
- **Rejected alternative:** exchanging on the page and passing the token to the app. The token would appear in a URL and in browser history.
- **Rejected alternative:** registering `macgit://` directly as GitHub's callback. The handoff page provides the "Open Commit+" fallback and a branded landing page, which the user asked for, and it matches the existing Commit+ sign-in handoff.

### The app exchanges the code through a commitplus.app route
The app calls `POST https://commitplus.app/api/git-providers/github/token` with JSON `{ "code", "code_verifier" }` and no Commit+ credentials.
- The route sends `client_id`, `client_secret`, the fixed `redirect_uri`, `code`, and `code_verifier` to `https://github.com/login/oauth/access_token` with `Accept: application/json`.
- It never takes a client ID or redirect URI from the request.
- It returns GitHub's success fields (`access_token`, `token_type`, `scope`, plus `refresh_token` and `expires_in` if GitHub ever sends them), or `{ error, error_description }`:
  - HTTP 400 for GitHub's `bad_verification_code` and other GitHub errors
  - HTTP 429 when rate-limited
  - HTTP 503 when the secret or GitHub is unavailable
- The secret is a server-only Vercel environment variable, never `NEXT_PUBLIC_*`.
- The route lives in `../landing-page`, next to `api/auth/app-token`. That repository's own docs own its validation and rate-limit details. This repository only depends on the request and response contract above.
- **Rejected alternative:** a Firebase Cloud Function. The callback page already lives on the Vercel app, and a Next.js route needs no Firebase deployment.
- **Rejected alternative:** a GitHub App instead of the OAuth app. It also needs a secret for the user-token exchange, and it would change the token type and permissions model.

### Session keeps two URLs
`GitProviderOAuthSession` gains an app callback URL, separate from `redirectURI`. `redirectURI` is the HTTPS URL sent to GitHub, and the exchange route uses it as a fixed value. `GitProviderOAuthCallback.parse` matches incoming URLs against the app callback URL. For GitLab's existing session, the app callback defaults to `redirectURI`, so its behavior is unchanged.

### Controller flow
`GitProviderAccountController` remains the owner.
- `connectGitHub()` and GitHub.com `reconnect(_:)` keep their account-limit checks, create a session (UUID `state`, PKCE verifier), store it as `pendingOAuthSession` with a start time, and open `GitHubProviderAuthService.authorizationURL(for:)`.
- `handleProviderOAuthCallback(_:)` dispatches on `session.provider`:
  - **GitHub:** a callback with `error=access_denied` and matching state ends the pending session silently. A valid code goes to `GitHubProviderAuthService.exchangeCallback(_:session:)`, then `fetchAccount`, then the existing `saveAuthorizedAccount`.
  - **GitLab:** keeps its existing path.
- A pending GitHub session older than 10 minutes, the code lifetime, is rejected and cleared.
- `cancelGitHubAuthorization()` clears the session.
- `connectGitHubWithDeviceCode()` clears the session and runs the existing `startGitHubDeviceAuthorization()`.
- The pending session lives only in memory. If the app quits mid-flow, the callback finds no session and the user sees "start again". This is acceptable because codes expire in 10 minutes anyway.

### Routing the callback to a live scene
- Add `.onOpenURL` to the Settings window, calling the same `providerAccountController.handleProviderOAuthCallback`.
- Add `macgit://git-provider` to the external-event lists: preferred by Settings, allowed by `ContentView` scenes.
- The repository `WindowGroup`'s `handlesExternalEvents(matching:)` must not match it, so a callback never spawns an empty repository window.
- The controller is shared, so whichever scene receives the URL completes the connection. Duplicate deliveries are harmless: the first one consumes `pendingOAuthSession`.
- No menu, toolbar, or notification commands are added. Callback handling is app-wide by design, because a connection belongs to the app, not to a repository window.

### UI
`GitProviderAddAccountSheet`'s GitHub pane replaces the immediate device-code view with a waiting state: "Finish connecting in your browser…", Cancel, and "Use a device code instead". The device-code UI (`GitProviderDeviceAuthorizationView`) is reused unchanged for the fallback. Errors use the controller's existing `errorMessage`.

## Risks / Trade-offs

- [The exchange route is a public, unauthenticated endpoint holding a secret] → It only accepts a code plus verifier for Commit+'s own client ID and fixed redirect URI, so it cannot be used to mint tokens for other apps. Rate limiting bounds abuse, and the device flow remains if the route is degraded.
- [The code briefly sits in the callback page URL and a `macgit://` URL] → Without the PKCE verifier, which stays in the app's memory, the code cannot be exchanged. The page strips its query, sets no-referrer, and is excluded from analytics.
- [The app shipped before the backend] → "Connect GitHub" would fail. Mitigation: deploy and verify the page and route first, register the callback URL, then release the app (see Migration Plan). The device fallback still works in that window.
- [Browser does not hand off to the app, for example Safari's prompt is dismissed] → The "Open Commit+" button and Cancel / device fallback in the app.
- [Scene routing on macOS is easy to get wrong] → Verify manually in four states: only Settings open, only Welcome open, a repository window open, and app relaunched mid-flow (expect "start again").

## Migration Plan

1. In `../landing-page`: add the callback page and the exchange route, set the server-only secret in Vercel, deploy, and verify with a real authorization against production.
2. In GitHub's OAuth app settings for Commit+: add `https://commitplus.app/oauth/github/callback` as a callback URL and keep Device Flow enabled.
3. Ship the macgit change. Existing connected accounts and their tokens are untouched; only new connections and reconnects use the web flow.
4. Rollback: an app build that calls the device flow directly, as today, needs no backend. The callback page and route can stay deployed unused.

## Open Questions

- The exact rate-limit values and storage for the exchange route. These are decided in `../landing-page` and don't change this contract.
