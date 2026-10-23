# github-account-connection Specification

## Purpose
Defines how Commit+ connects and reconnects a GitHub.com account in Settings → Connections through GitHub's OAuth web flow, with a device-code fallback.

## Requirements

### Requirement: GitHub.com connects through the browser by default
Choosing "Connect GitHub" or "Reconnect" for a GitHub.com account SHALL open GitHub's authorization page in the default browser, requesting the same scopes as today. While authorization is pending, the connection UI SHALL show that Commit+ is waiting for the browser and offer Cancel.

#### Scenario: Start connecting
- **WHEN** the user chooses "Connect GitHub" in Settings → Connections
- **THEN** GitHub's authorization page for Commit+ opens in the default browser
- **AND** the connection UI shows a waiting state with Cancel and "Use a device code instead"

#### Scenario: Reconnect an account that needs reauthorization
- **WHEN** the user chooses "Reconnect" on a GitHub.com account
- **THEN** the same browser authorization starts for that account

### Requirement: Authorization returns to the app through commitplus.app
After the user approves, GitHub SHALL redirect to a commitplus.app callback page, which SHALL hand the result back to Commit+ through the `macgit://` URL scheme. The page SHALL offer a manual "Open Commit+" action if the app does not open automatically, and SHALL NOT exchange the code or display it.

#### Scenario: Approve in the browser
- **WHEN** the user approves Commit+ on GitHub's authorization page
- **THEN** the browser lands on the commitplus.app callback page
- **AND** Commit+ is opened with the authorization result

#### Scenario: App does not open automatically
- **WHEN** the browser blocks or ignores the automatic hand-off to Commit+
- **THEN** the callback page shows an "Open Commit+" button that completes the hand-off

### Requirement: Callbacks are verified before use
Commit+ SHALL accept an authorization result only for a GitHub connection it started on this Mac, with a matching `state`, and within the authorization lifetime. Any other callback SHALL be rejected without contacting the token-exchange service.

#### Scenario: Matching callback
- **WHEN** Commit+ receives a callback whose `state` matches the pending GitHub connection
- **THEN** it completes the connection

#### Scenario: Forged or stale callback
- **WHEN** Commit+ receives a GitHub callback with an unknown or mismatched `state`, or after the pending connection was cancelled or expired
- **THEN** no account is connected
- **AND** no token exchange is attempted

### Requirement: The client secret never reaches the app
The authorization code SHALL be exchanged for a token by a commitplus.app service that holds Commit+'s GitHub OAuth client secret. The app SHALL send only the code and its PKCE verifier. The secret SHALL NOT be included in the app, its configuration, or any URL.

#### Scenario: Successful exchange
- **WHEN** Commit+ sends a valid code and PKCE verifier to the exchange service
- **THEN** it receives a GitHub access token
- **AND** the connected account appears in Settings → Connections with the GitHub username

#### Scenario: Code intercepted without the verifier
- **WHEN** an exchange request carries a valid code but a wrong or missing PKCE verifier
- **THEN** the exchange fails and no token is issued

### Requirement: Tokens stay out of the browser and synced data
The access token SHALL travel only from the exchange service to the app over HTTPS and SHALL be stored only in this Mac's Keychain, as device-flow tokens are. Tokens SHALL NOT appear in a URL, the callback page, logs, or synced settings.

#### Scenario: Browser history after connecting
- **WHEN** a GitHub account has been connected through the web flow
- **THEN** no URL visited in the browser contains the access token

### Requirement: Device code remains available as a fallback
The connection UI SHALL offer "Use a device code instead", which SHALL run the existing GitHub device flow and cancel any pending browser authorization.

#### Scenario: Switch to the device code
- **WHEN** the user chooses "Use a device code instead" while browser authorization is pending
- **THEN** the pending browser authorization is cancelled
- **AND** Commit+ shows a GitHub device code and connects the account once it is approved

### Requirement: The exchange service is usable without a Commit+ account
The exchange service SHALL serve signed-out Commit+ users and SHALL limit the request rate per client. A rate-limited or unavailable exchange SHALL fail with a message that suggests retrying later or using a device code.

#### Scenario: Signed-out user connects GitHub
- **WHEN** a user who is not signed in to Commit+ connects GitHub through the browser
- **THEN** the connection completes without asking them to sign in to Commit+

#### Scenario: Exchange unavailable
- **WHEN** the exchange service is unreachable, rate-limited, or returns an error
- **THEN** the connection fails with a message offering to try again or use a device code
- **AND** no partial account is saved

### Requirement: Failures and cancellation leave no connection behind
Denying access on GitHub, cancelling in Commit+, or letting the authorization expire SHALL end the pending connection without saving an account. A denial SHALL NOT be reported as an error.

#### Scenario: User denies access on GitHub
- **WHEN** the user chooses Cancel on GitHub's authorization page
- **THEN** Commit+ returns to its idle connection state without an error message

#### Scenario: Cancel in Commit+
- **WHEN** the user chooses Cancel in Commit+ while browser authorization is pending
- **THEN** a later callback for that attempt is ignored

#### Scenario: Authorization expires
- **WHEN** no callback arrives within the authorization lifetime
- **THEN** the pending connection ends with a message to try again

### Requirement: Existing account rules still apply
Free-plan account limits, duplicate-account detection, and the connected account's identity, scopes, and token status SHALL behave as they do for device-flow connections. GitHub Enterprise Server accounts SHALL keep using personal access tokens or SSH.

#### Scenario: Free-plan limit reached
- **WHEN** a Free-plan user at the account limit chooses "Connect GitHub"
- **THEN** the browser does not open
- **AND** the existing account-limit message is shown

#### Scenario: Reconnecting the same GitHub user
- **WHEN** the web flow completes for a GitHub user who is already connected
- **THEN** the existing account's token is replaced rather than a duplicate account being added
