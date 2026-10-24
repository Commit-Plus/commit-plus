# Spec Delta

## Purpose

Defines how Commit+ connects one Jira Cloud site to this Mac with an Atlassian API token in Settings → Integrations, so the Jira issue list can read the user's issues without sending the credential to Commit+ services.

## ADDED Requirements

### Requirement: Jira Cloud connects with site, email, and API token
Settings → Integrations SHALL offer a Jira section with "Connect Jira" that asks for the Jira Cloud site, the Atlassian account email, and an Atlassian API token, and SHALL link to Atlassian's API token page. Only Jira Cloud sites on `atlassian.net` over HTTPS SHALL be accepted; a bare site name SHALL be completed to `https://<name>.atlassian.net`.

#### Scenario: Open the connect form
- **WHEN** the user chooses "Connect Jira" in Settings → Integrations
- **THEN** a form asks for the site, email, and API token
- **AND** it offers a link that opens Atlassian's API token management page in the browser

#### Scenario: Bare site name
- **WHEN** the user enters `acme` as the site
- **THEN** Commit+ uses `https://acme.atlassian.net`

#### Scenario: Unsupported site
- **WHEN** the user enters an HTTP URL or a host outside `atlassian.net`
- **THEN** the form shows that only Jira Cloud sites are supported and does not contact the host

### Requirement: Credentials are validated before they are saved
Commit+ SHALL verify the site, email, and token against Jira before saving the connection, and SHALL save nothing when verification fails. A successful connection SHALL show the Jira account's display name, email, and site.

#### Scenario: Valid credentials
- **WHEN** the user submits a site, email, and token that Jira accepts
- **THEN** the connection is saved and the Jira section shows the account name, email, and site

#### Scenario: Rejected credentials
- **WHEN** Jira rejects the email or token
- **THEN** the form shows that the email or API token was not accepted
- **AND** no connection or token is saved

#### Scenario: Site unreachable
- **WHEN** the site cannot be reached or does not respond as Jira Cloud
- **THEN** the form shows that the Jira site could not be reached
- **AND** no connection or token is saved

### Requirement: The Jira credential stays on this Mac
The API token SHALL be stored only in the macOS Keychain, scoped to the signed-in Commit+ account. The connection SHALL NOT be synced through Commit+ Cloud and SHALL NOT be sent to Commit+ services; it SHALL be sent only to the connected Jira site. The token SHALL NOT appear in logs, error messages, or the UI after it is saved.

#### Scenario: Another Mac
- **WHEN** the user signs in to the same Commit+ account on another Mac
- **THEN** no Jira connection appears there until the user connects Jira on that Mac

#### Scenario: Different Commit+ account
- **WHEN** a different Commit+ account signs in on the same Mac
- **THEN** that account does not see or use the previous account's Jira connection

#### Scenario: Error while loading issues
- **WHEN** a Jira request fails
- **THEN** the error shown to the user does not include the token

### Requirement: Only one Jira site is connected at a time
Commit+ SHALL keep at most one Jira connection per Commit+ account on this Mac. Connecting while a connection exists SHALL require removing or replacing the existing one.

#### Scenario: Already connected
- **WHEN** a Jira connection exists
- **THEN** the Jira section shows that connection with Reconnect and Remove, not "Connect Jira"

### Requirement: Rejected tokens can be reconnected
When Jira rejects a saved token, the connection SHALL be marked as needing reconnection and Commit+ SHALL offer "Reconnect", which asks for a new token for the same site and email and replaces the saved token only after the new one is verified.

#### Scenario: Token revoked or expired
- **WHEN** a Jira request returns an authentication failure for the saved token
- **THEN** the Jira section and the Jira issues screen show that the connection needs to be reconnected

#### Scenario: Reconnect with a valid token
- **WHEN** the user reconnects with a new token that Jira accepts
- **THEN** the old token is replaced and the connection is usable again

#### Scenario: Reconnect with an invalid token
- **WHEN** the user reconnects with a token that Jira rejects
- **THEN** the saved connection is left unchanged and still needs reconnection

### Requirement: Removing the connection deletes the credential
"Remove" SHALL delete the Jira connection and its Keychain token from this Mac after confirmation. It SHALL NOT revoke the token at Atlassian, and the confirmation SHALL say so.

#### Scenario: Remove
- **WHEN** the user confirms removing the Jira connection
- **THEN** the connection and token are deleted from this Mac
- **AND** the Jira issues screen shows that no Jira site is connected

### Requirement: Connecting Jira requires sign-in but not Pro
Connecting Jira SHALL require a signed-in Commit+ account, because the token is scoped to that account. Signed-in users SHALL be able to connect and remove a Jira site on any plan; the Pro requirement applies to the Jira issues screen.

#### Scenario: Signed out
- **WHEN** no Commit+ account is signed in
- **THEN** the Jira section offers Sign In instead of "Connect Jira"

#### Scenario: Free user connects Jira
- **WHEN** a signed-in Free user connects Jira in Settings → Integrations
- **THEN** the connection is saved
- **AND** opening the Jira issues screen still shows the Pro upgrade view
