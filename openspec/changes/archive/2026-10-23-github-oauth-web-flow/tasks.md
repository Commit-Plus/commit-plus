# Tasks

## 1. commitplus.app callback and exchange (../landing-page)

- [x] 1.1 Add the `/oauth/github/callback` page. It forwards `code`/`state` (or `error`/`state`) to `macgit://git-provider/oauth/github/callback`, strips its own query, shows an "Open Commit+" button, sends `Referrer-Policy: no-referrer` and `Cache-Control: no-store`, and is excluded from Vercel Analytics. Verify with `pnpm build` and by loading the page locally with sample query values: it redirects to the expected `macgit://` URL, and the address bar ends without the query.
- [x] 1.2 Add `POST /api/git-providers/github/token`. It accepts `{code, code_verifier}`, validates both, and calls GitHub's token endpoint with the server-only client ID, secret, and fixed redirect URI. It returns the token fields or `{error, error_description}` with 400, 429, or 503, applies per-client rate limiting, and never logs the code, verifier, or token. Verify with route tests (no emulator) for success pass-through, a GitHub error, a missing or invalid body, a missing secret (503), and rate limiting (429), plus `pnpm build`.
- [x] 1.3 Document the server-only environment variable for the GitHub OAuth client secret in `../landing-page`'s `.env.example` and its docs, without a real value. Verify by reviewing the diff.

## 2. Native OAuth plumbing

- [x] 2.1 Give `GitProviderOAuthSession` an app callback URL separate from `redirectURI` (defaulting to it), and make `GitProviderOAuthCallback.parse` match against the app callback URL. Verify with new cases in `GitProviderOAuthTests` (GitHub session: HTTPS redirect, `macgit://` callback accepted, mismatched path rejected, error callback surfaced) while existing GitLab cases still pass.
- [x] 2.2 Add `authorizationURL(for:)` and `exchangeCallback(_:session:)` to `GitHubProviderAuthService`. The authorization URL carries `client_id`, `redirect_uri`, `scope`, `state`, `code_challenge`, and `code_challenge_method=S256`. The exchange posts `{code, code_verifier}` to the commitplus.app route and maps 400, 429, 503, and network errors to `GitProviderAuthError` messages that offer retry or a device code. Verify with new cases in `GitHubProviderAuthServiceTests` using the existing HTTP client fake, including that no request contains a client secret.

## 3. Controller flow and routing

- [x] 3.1 Route `connectGitHub()` and GitHub.com `reconnect(_:)` through the web flow after the existing account-limit checks. Add `cancelGitHubAuthorization()` and `connectGitHubWithDeviceCode()`, extend `handleProviderOAuthCallback(_:)` to complete GitHub callbacks (silent end on `access_denied`, rejection after 10 minutes or after cancel, no exchange on a state mismatch), and save through `saveAuthorizedAccount`. Verify with new cases in `GitProviderAccountControllerTests`: success, denial, cancel-then-late-callback, expiry, state mismatch (no exchange call), Free-plan limit (browser not opened), reconnect of an existing GitHub user (token replaced, no duplicate), and device fallback.
- [x] 3.2 Add `.onOpenURL` and `macgit://git-provider` external-event handling to the Settings window, and allow it in `ContentView` scenes, without adding it to the repository `WindowGroup`'s `matching` list. Verify with an app build.
- [x] 3.3 Update the GitHub pane of `GitProviderAddAccountSheet` with the browser waiting state (Cancel, "Use a device code instead"), and reuse `GitProviderDeviceAuthorizationView` for the fallback. Verify with an app build.

## 4. Rollout (requires explicit authorization)

- [x] 4.1 With explicit user authorization, deploy the `../landing-page` change to production on Vercel and set the secret as a server-only environment variable. Verify that the production callback page loads and the exchange route returns 400 for a fake code (and not 503).
- [x] 4.2 With explicit user authorization, add `https://commitplus.app/oauth/github/callback` to the Commit+ GitHub OAuth app's callback URLs and confirm Device Flow stays enabled. Verify by reviewing the OAuth app settings page.

## 5. Integration checks

- [x] 5.1 Run `xcodebuild … -only-testing:macgitTests/GitProviderOAuthTests -only-testing:macgitTests/GitHubProviderAuthServiceTests -only-testing:macgitTests/GitProviderAccountControllerTests -only-testing:macgitTests/SelfHostedGitProviderTests test` and verify that all pass.
- [ ] 5.2 Manual end-to-end review against production after 4.1 and 4.2. Record the results in the PR description:
  - Connect a new GitHub account starting from Settings → Connections with only the Settings window open, then with a repository window open.
  - Deny on GitHub, cancel in Commit+, and use the device-code fallback.
  - Reconnect an existing account.
  - Quit the app mid-flow and confirm the "start again" message.
  - Check that the browser history contains no token and that the Keychain holds the new token.
