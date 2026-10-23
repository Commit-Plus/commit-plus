# Proposal

## Why

GitHub.com accounts now connect through the browser (`github-oauth-web-flow`), but GitLab.com in Settings → Connections still shows a device code. GitLab only moved to the device flow in July because the GitHub connection did, and commitplus.app had no callback URL to register at the time. Now that the domain and the GitHub callback page are live, GitLab should connect the same way so both providers behave alike.

## What Changes

- "Connect GitLab" and "Reconnect" for GitLab.com open GitLab's authorization page (`/oauth/authorize`) with `state` and a PKCE S256 challenge, instead of showing a device code.
- GitLab redirects to a new HTTPS callback page, `https://commitplus.app/oauth/gitlab/callback`. Like the GitHub page, it forwards only `code` and `state` (or GitLab's error) to `macgit://git-provider/oauth/gitlab/callback` and never exchanges the code.
- Commit+ verifies `state`, then exchanges the code **directly with GitLab** (`/oauth/token`) using the PKCE verifier. Commit+'s GitLab application is non-confidential, so no client secret is needed and no commitplus.app token endpoint is added. Tokens, including refresh tokens, are stored in the existing Keychain token vault, as device-flow tokens are today.
- The device flow stays available as a fallback ("Use a device code instead"), with the same waiting, Cancel, and 10-minute expiry behavior as GitHub.
- The browser-waiting state in the controller and the add-account sheet becomes provider-neutral, so GitHub and GitLab share it. GitHub's behavior is unchanged.
- Scopes (`api read_user write_repository`), token refresh, account identity, and Free-plan account limits are unchanged.
- Out of scope: self-hosted GitLab (it keeps personal access tokens and SSH), Bitbucket, and GitHub.

## Capabilities

### New Capabilities
- `gitlab-account-connection`: How a GitLab.com account is connected and reconnected in Settings → Connections. Covers the browser authorization, the commitplus.app callback handoff, the direct PKCE token exchange, the device-code fallback, and failure handling.

### Modified Capabilities
<!-- None. `github-account-connection` is not archived yet, and its requirements do not change. -->

## Impact

- **macgit code:** `GitLabProviderAuthConfiguration` (HTTPS redirect URI plus app callback URL), `GitProviderAccountController` (GitLab browser flow, device fallback, provider-neutral waiting state), and the GitLab pane of `GitProviderAddAccountSheet`. `GitLabProviderAuthService.authorizationURL` / `exchangeCallback` and the callback routing added for GitHub are reused.
- **../landing-page (cross-repository):** a `/oauth/gitlab/callback` route that shares the GitHub callback page's code. No API route, no secret, and no new environment variable. Needs a production deployment on Vercel.
- **GitLab application settings (operational):** on Commit+'s GitLab.com application (client ID `50647b51…`), add `https://commitplus.app/oauth/gitlab/callback` as a redirect URI and keep "Confidential" off.
- **Firebase:** none.
- **Rollout dependency:** the app change must not ship before the callback page is deployed and the redirect URI is registered. Until then, "Connect GitLab" would fail; the device fallback would still work.
