# chatgpt-codex-provider Specification

## Purpose
Lets a user connect a ChatGPT account, including ChatGPT Free, through the unofficial Codex sign-in and use its Codex allowance for Commit+ AI features, separately from the OpenAI API key and official ChatGPT providers.

## Requirements

### Requirement: Separate unofficial provider
The system SHALL offer "ChatGPT (Codex) — Unofficial" as its own entry in "Add Provider…", separate from the OpenAI and official ChatGPT providers. Configuring, using, or removing one of these providers SHALL NOT change the others' credentials, models, or availability.

#### Scenario: Providers stay independent
- **WHEN** the user has an OpenAI API key and an official ChatGPT sign-in, and connects the Codex provider
- **THEN** all three providers are listed separately and the OpenAI key and the ChatGPT sign-in are unchanged

#### Scenario: Removing the Codex provider
- **WHEN** the user disconnects the Codex provider
- **THEN** the OpenAI and official ChatGPT providers stay configured and available

### Requirement: Risk acknowledgment before first sign-in
Before the first sign-in on this Mac, the system SHALL require the user to acknowledge three things: the provider uses an interface OpenAI does not support, it may stop working at any time, and the user uses it at their own risk under OpenAI's terms. The configuration sheet SHALL always label the provider as unofficial.

#### Scenario: Sign-in without acknowledgment
- **WHEN** the user has not acknowledged the risk and opens the Codex provider sheet
- **THEN** the sign-in button is disabled until the user acknowledges the notice

#### Scenario: Acknowledgment is remembered
- **WHEN** the user acknowledged the notice earlier and signs in again after disconnecting
- **THEN** sign-in starts without asking again, and the unofficial label is still shown

### Requirement: Browser sign-in with loopback callback
The system SHALL sign in through the default browser with PKCE and a `state` check, receive the callback on a local loopback listener, and offer the sign-in link with a Copy Link action while it waits. The listener SHALL close on success, failure, cancel, sheet dismissal, or after 10 minutes.

#### Scenario: Successful sign-in
- **WHEN** the user completes sign-in in the browser
- **THEN** the sheet shows the account email and ChatGPT plan type, and the provider becomes selectable

#### Scenario: Wrong browser profile
- **WHEN** the browser opens in a profile that is not signed in to the intended account
- **THEN** the user can copy the sign-in link from the sheet and open it in another profile

#### Scenario: Callback with a wrong state
- **WHEN** the listener receives a callback whose `state` does not match the pending sign-in
- **THEN** the callback is ignored, no tokens are stored, and the sign-in keeps waiting

#### Scenario: Sign-in times out
- **WHEN** no valid callback arrives within 10 minutes
- **THEN** the listener closes and the sheet shows that sign-in timed out

### Requirement: Local token storage
The system SHALL store the Codex tokens only in this Mac's Keychain, separately from the official ChatGPT tokens. The tokens SHALL NOT be synced, logged, or included in model context. The system SHALL refresh the access token before it expires, and concurrent requests SHALL share one refresh.

#### Scenario: Tokens are not synced
- **WHEN** the user signs in and cloud settings sync runs
- **THEN** the synced settings contain no Codex token, account ID, or email

#### Scenario: Concurrent refresh
- **WHEN** two AI requests start while the access token is about to expire
- **THEN** one refresh request is sent and both AI requests use the refreshed token

#### Scenario: Refresh rejected
- **WHEN** the token endpoint rejects the refresh token
- **THEN** the local tokens are deleted and the provider asks the user to sign in again

### Requirement: AI features served
Once signed in, the provider SHALL serve commit-message generation, repository chat, repository agent turns, and conflict resolution. Agent mutations SHALL keep the existing confirmation and revalidation.

#### Scenario: Commit message generation
- **WHEN** the Codex provider is selected and the user generates a commit message
- **THEN** the request is sent to ChatGPT's Codex backend with the account's credentials, and the message is shown

#### Scenario: Agent mutation still needs confirmation
- **WHEN** the agent proposes a repository mutation through the Codex provider
- **THEN** the user must confirm the mutation before it runs, as with other providers

### Requirement: Failures do not fall back silently
When the Codex backend rejects a request, for example because the usage limit was reached, the plan is not allowed, the sign-in was revoked, or the client is blocked, the system SHALL report the provider unavailable with a message naming the cause. It SHALL NOT switch to another provider by itself.

#### Scenario: Usage limit reached
- **WHEN** the backend reports that the account's Codex usage limit is reached
- **THEN** the request fails with a usage-limit message, the provider is shown unavailable for a while, and no other provider is called

#### Scenario: Client blocked by OpenAI
- **WHEN** sign-in or a request fails because OpenAI no longer accepts the unofficial client
- **THEN** the user sees that the unofficial ChatGPT (Codex) connection is not working, and can still disconnect it

### Requirement: Commit+ Pro gate
Connecting and using the Codex provider SHALL require Commit+ Pro through the `aiBringYourOwnKey` feature key, evaluated like the official ChatGPT provider, including the local policy fallback when the feature policy is unavailable. Disconnecting SHALL remain allowed without Pro.

#### Scenario: Free Commit+ user
- **WHEN** a Commit+ Free user opens the Codex provider sheet
- **THEN** sign-in is unavailable and the sheet offers the Commit+ Pro upgrade

#### Scenario: Lapsed Pro
- **WHEN** a user connected the Codex provider and their Commit+ Pro has lapsed
- **THEN** the provider cannot be selected or used, but the user can still disconnect it

### Requirement: Disconnect
The system SHALL let the user disconnect after confirming. Disconnecting SHALL try to revoke the refresh token and SHALL delete the local tokens even when revocation fails. If the Codex provider was the default, the default SHALL revert to Apple Intelligence.

#### Scenario: Disconnect while offline
- **WHEN** the user disconnects and the revocation request fails
- **THEN** the local tokens are still deleted and the provider shows as not connected

#### Scenario: Disconnect the default provider
- **WHEN** the Codex provider is the default and the user disconnects it
- **THEN** the default provider becomes Apple Intelligence
