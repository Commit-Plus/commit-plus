# Proposal

## Why

Connecting a GitHub.com account in Settings → Connections currently uses GitHub's device flow: the user copies an eight-character code into a browser page and Commit+ polls until GitHub confirms. The standard OAuth web application flow is one click in the browser, returns straight to the app, and matches how users connect other desktop tools. Commit+ already has the pieces for it (an OAuth callback parser, PKCE, the `macgit://` URL scheme, and a commitplus.app → app handoff for Commit+ sign-in); GitHub is the one provider still limited to the device flow.

## What Changes

- "Connect GitHub" and "Reconnect" for GitHub.com open GitHub's authorization page (`login/oauth/authorize`) with `state` and a PKCE S256 challenge, instead of showing a device code.
- GitHub redirects to an HTTPS callback page on commitplus.app. The page forwards only the authorization `code` and `state` (or GitHub's error) to Commit+ through the `macgit://` URL scheme. It never exchanges the code itself.
- Commit+ verifies `state`, then sends the code and PKCE verifier to a new commitplus.app token-exchange endpoint. The endpoint adds Commit+'s GitHub OAuth `client_secret`, which cannot ship inside the open-source app, and returns the token to the app. The token is stored in the existing Keychain token vault, as device-flow tokens are today.
- The device flow stays available as a fallback ("Use a device code instead"). Use it when the browser handoff or commitplus.app is unavailable.
- The exchange endpoint is open to signed-out Commit+ users, as connecting GitHub is today, and is rate-limited.
- Scopes, account identity, Free-plan account limits, and GitHub Enterprise Server behavior (personal access token or SSH) are unchanged.
- Out of scope: GitLab's web flow, Bitbucket, and GitHub Copilot access. Copilot uses its own sign-in, and this OAuth app's tokens never grant Copilot.

## Capabilities

### New Capabilities
- `github-account-connection`: How a GitHub.com account is connected and reconnected in Settings → Connections. Covers the browser authorization, the commitplus.app callback handoff, the server-side token exchange, the device-code fallback, and failure handling.

### Modified Capabilities
<!-- None: no existing spec covers Git provider accounts. -->

## Impact

- **macgit code:** `GitHubProviderAuthService` (authorization URL, callback exchange through commitplus.app), `GitProviderAccountController` (start web flow, route the GitHub callback, device fallback), `GitProviderOAuthModels` (a session whose app callback differs from the provider redirect URI), and the GitHub connect UI in `GitProviderAddAccountSheet` / Settings → Connections. App scene URL routing for the new `macgit://` callback path.
- **../landing-page (cross-repository):** a new callback page under the commitplus.app Next.js app, and a new server route that holds the GitHub OAuth `client_secret` and calls `https://github.com/login/oauth/access_token`, with rate limiting. Both require a production deployment on Vercel, plus the secret configured as a server-only environment variable.
- **GitHub OAuth app settings (operational):** add the commitplus.app callback URL to Commit+'s OAuth app (client ID `Ov23lictC3FXsN0kjsbs`) and keep "Enable Device Flow" on for the fallback.
- **Firebase:** none. No Firestore paths, rules, synced settings, or Cloud Functions change.
- **Rollout dependency:** the app change must not ship before the callback page and exchange endpoint are deployed and the callback URL is registered. Otherwise "Connect GitHub" fails in production.
