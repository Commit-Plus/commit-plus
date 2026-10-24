# Tasks

## 1. commitplus.app callback (../landing-page)

- [x] 1.1 Generalize `lib/github-oauth.ts` into a provider-keyed helper (GitHub and GitLab redirect and app callback URLs) and share the callback page renderer, without changing the GitHub page's output. Verify that the existing `tests/github-oauth-callback.test.mjs` and `tests/github-oauth-token.test.mjs` still pass unchanged.
- [x] 1.2 Add `GET /oauth/gitlab/callback`. It forwards `code`/`state` (or `error`/`state`) to `macgit://git-provider/oauth/gitlab/callback` with the same headers, CSP, query stripping, "Open Commit+" button, and GitLab wording, and returns 400 for invalid input. Verify with a new `tests/gitlab-oauth-callback.test.mjs` (success with a 64-hex code, denial, invalid input, headers), `pnpm build`, and a local `pnpm start` request.
- [x] 1.3 Add the GitLab callback and the GitLab application settings (redirect URI, non-confidential, scopes) to `../landing-page`'s OAuth docs. Verify by reviewing the diff.

## 2. Native configuration

- [x] 2.1 Give `GitLabProviderAuthConfiguration` the HTTPS `redirectURI` `https://commitplus.app/oauth/gitlab/callback` and an `appCallbackURL` `macgit://git-provider/oauth/gitlab/callback`. Verify with `GitLabProviderAuthServiceTests` cases: the authorization URL carries the HTTPS `redirect_uri`, `state`, and S256 challenge; the exchange sends the same `redirect_uri` and `code_verifier` and no `client_secret`; and `GitProviderOAuthTests` accepts a GitLab session's `macgit://…/gitlab/callback` URL and rejects the GitHub callback path for it.

## 3. Controller flow

- [x] 3.1 Make the browser-waiting state provider-neutral: replace `isAwaitingGitHubBrowserAuthorization` with `awaitingBrowserAuthorizationProvider`, `cancelGitHubAuthorization()` with `cancelBrowserAuthorization()`, and share the session start and expiry logic. Update the existing GitHub cases in `GitProviderAccountControllerTests` to the new names and verify that they all still pass.
- [x] 3.2 Route `connectGitLabDotCom()` and GitLab.com `reconnect(_:)` through the browser flow after the existing limit checks, add `connectGitLabWithDeviceCode()`, and remove `startGitLabOAuth(host:)`. Verify with new `GitProviderAccountControllerTests` cases: success (token with refresh token saved), denial, cancel-then-late-callback, expiry, state mismatch (no exchange), a GitHub callback while GitLab is pending (ignored, still waiting), Free-plan limit (browser not opened), reconnect of an existing GitLab user (token replaced, no duplicate), self-hosted reconnect (no browser), and device fallback.

## 4. UI

- [x] 4.1 Drive the waiting pane, Cancel, and "Use a device code instead" in `GitProviderAddAccountSheet` from `awaitingBrowserAuthorizationProvider` for both GitHub and GitLab, with `useDeviceCode()` calling the fallback for the selected provider. Verify with an app build.

## 5. Rollout (requires explicit authorization)

- [x] 5.1 With explicit user authorization, deploy the `../landing-page` change to production on Vercel. Verify that `https://commitplus.app/oauth/gitlab/callback?code=…&state=…` renders the handoff page and the GitHub callback page is unchanged.
- [x] 5.2 On Commit+'s GitLab.com application, add `https://commitplus.app/oauth/gitlab/callback` as a redirect URI, keep `macgit://git-provider/oauth/callback`, and confirm "Confidential" is off and the scopes are unchanged. Verify by reviewing the application settings page.

## 6. Integration checks

- [x] 6.1 Run `xcodebuild … -only-testing:macgitTests/GitProviderOAuthTests -only-testing:macgitTests/GitLabProviderAuthServiceTests -only-testing:macgitTests/GitHubProviderAuthServiceTests -only-testing:macgitTests/GitProviderAccountControllerTests -only-testing:macgitTests/SelfHostedGitProviderTests test` and verify that all pass. Run `git diff --check`.
- [ ] 6.2 Manual end-to-end review against production after 5.1 and 5.2. Record the results in the PR description:
  - Connect a new GitLab.com account from Settings → Connections, with only Settings open and with a repository window open.
  - Deny on GitLab, cancel in Commit+, and use the device-code fallback.
  - Reconnect an existing GitLab account.
  - Force a token refresh (for example, wait past the 2-hour expiry or edit the stored expiry in a Debug build) and confirm Git operations still work without reconnecting.
  - Repeat one GitHub connection to confirm it is unchanged.
