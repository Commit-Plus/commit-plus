# Spec Delta

## Purpose

Defines how Commit+ connects and reconnects a GitLab.com account in Settings → Connections through GitLab's OAuth authorization code flow with PKCE, with a device-code fallback.

## ADDED Requirements

### Requirement: GitLab.com connects through the browser by default
Choosing "Connect GitLab" or "Reconnect" for a GitLab.com account SHALL open GitLab's authorization page in the default browser, requesting the same scopes as today. While authorization is pending, the connection UI SHALL show that Commit+ is waiting for the browser and offer Cancel.

#### Scenario: Start connecting
- **WHEN** the user chooses "Connect GitLab" for GitLab.com in Settings → Connections
- **THEN** GitLab's authorization page for Commit+ opens in the default browser
- **AND** the connection UI shows a waiting state with Cancel and "Use a device code instead"

#### Scenario: Reconnect an account that needs reauthorization
- **WHEN** the user chooses "Reconnect" on a GitLab.com account
- **THEN** the same browser authorization starts for that account

### Requirement: Authorization returns to the app through commitplus.app
After the user approves, GitLab SHALL redirect to a commitplus.app callback page, which SHALL hand the result back to Commit+ through the `macgit://` URL scheme. The page SHALL offer a manual "Open Commit+" action if the app does not open automatically, and SHALL NOT exchange the code or display it.

#### Scenario: Approve in the browser
- **WHEN** the user approves Commit+ on GitLab's authorization page
- **THEN** the browser lands on the commitplus.app GitLab callback page
- **AND** Commit+ is opened with the authorization result

#### Scenario: App does not open automatically
- **WHEN** the browser blocks or ignores the automatic hand-off to Commit+
- **THEN** the callback page shows an "Open Commit+" button that completes the hand-off

### Requirement: Callbacks are verified before use
Commit+ SHALL accept an authorization result only for a GitLab connection it started on this Mac, with a matching `state`, and within the authorization lifetime. Any other callback SHALL be rejected without contacting GitLab's token endpoint.

#### Scenario: Matching callback
- **WHEN** Commit+ receives a GitLab callback whose `state` matches the pending GitLab connection
- **THEN** it completes the connection

#### Scenario: Forged or stale callback
- **WHEN** Commit+ receives a GitLab callback with an unknown or mismatched `state`, or after the pending connection was cancelled or expired
- **THEN** no account is connected
- **AND** no token exchange is attempted

#### Scenario: Callback for the other provider
- **WHEN** a GitHub callback arrives while a GitLab connection is pending
- **THEN** the GitLab connection keeps waiting and no exchange is attempted

### Requirement: The code is exchanged directly with GitLab using PKCE
Commit+ SHALL exchange the authorization code at GitLab's token endpoint with its PKCE verifier and SHALL NOT send a client secret. No commitplus.app service SHALL take part in the exchange.

#### Scenario: Successful exchange
- **WHEN** Commit+ exchanges a valid code with its PKCE verifier
- **THEN** it receives a GitLab access token and refresh token
- **AND** the connected account appears in Settings → Connections with the GitLab username

#### Scenario: Code intercepted without the verifier
- **WHEN** a token request carries a valid code but a wrong or missing PKCE verifier
- **THEN** GitLab issues no token

#### Scenario: GitLab rejects the exchange
- **WHEN** GitLab's token endpoint returns an error or cannot be reached
- **THEN** the connection fails with a message
- **AND** no partial account is saved

### Requirement: Tokens stay out of the browser and synced data
GitLab tokens SHALL travel only from GitLab's token endpoint to the app over HTTPS and SHALL be stored only in this Mac's Keychain, as device-flow tokens are. Tokens SHALL NOT appear in a URL, the callback page, logs, or synced settings. Token refresh SHALL keep working as it does for device-flow tokens.

#### Scenario: Browser history after connecting
- **WHEN** a GitLab account has been connected through the browser
- **THEN** no URL visited in the browser contains the access or refresh token

#### Scenario: Expired access token
- **WHEN** a browser-connected GitLab account's access token has expired
- **THEN** Commit+ refreshes it with the stored refresh token without asking the user to reconnect

### Requirement: Device code remains available as a fallback
The connection UI SHALL offer "Use a device code instead", which SHALL run the existing GitLab device flow and cancel any pending browser authorization.

#### Scenario: Switch to the device code
- **WHEN** the user chooses "Use a device code instead" while GitLab browser authorization is pending
- **THEN** the pending browser authorization is cancelled
- **AND** Commit+ shows a GitLab device code and connects the account once it is approved

### Requirement: Failures and cancellation leave no connection behind
Denying access on GitLab, cancelling in Commit+, or letting the authorization expire SHALL end the pending connection without saving an account. A denial SHALL NOT be reported as an error.

#### Scenario: User denies access on GitLab
- **WHEN** the user chooses Deny on GitLab's authorization page
- **THEN** Commit+ returns to its idle connection state without an error message

#### Scenario: Cancel in Commit+
- **WHEN** the user chooses Cancel in Commit+ while GitLab browser authorization is pending
- **THEN** a later callback for that attempt is ignored

#### Scenario: Authorization expires
- **WHEN** no callback arrives within 10 minutes
- **THEN** the pending connection ends with a message to try again

### Requirement: Existing account rules still apply
Free-plan account limits, duplicate-account detection, and the connected account's identity, scopes, and token status SHALL behave as they do for device-flow connections. Self-hosted GitLab accounts SHALL keep using personal access tokens or SSH.

#### Scenario: Free-plan limit reached
- **WHEN** a Free-plan user at the account limit chooses "Connect GitLab"
- **THEN** the browser does not open
- **AND** the existing account-limit message is shown

#### Scenario: Reconnecting the same GitLab user
- **WHEN** the browser flow completes for a GitLab user who is already connected
- **THEN** the existing account's token is replaced rather than a duplicate account being added

#### Scenario: Self-hosted GitLab
- **WHEN** the user adds or reconnects a self-hosted GitLab account
- **THEN** Commit+ asks for a personal access token or SSH key, as today, and does not open a browser authorization
