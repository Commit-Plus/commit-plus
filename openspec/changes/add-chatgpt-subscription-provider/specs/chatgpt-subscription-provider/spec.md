# Spec Delta

## Purpose

Lets a ChatGPT Plus or Pro subscriber connect their plan as a Commit+ AI provider through OpenAI's official "Sign in with ChatGPT" OAuth, using their plan allowance instead of an API key.

## ADDED Requirements

### Requirement: ChatGPT is offered as an addable AI provider
Settings → AI SHALL list ChatGPT in the "Add Provider…" menu while it is not connected, and in the Providers table once connected. It SHALL be distinct from the API-key OpenAI provider, and both MAY be connected at once.

#### Scenario: Both OpenAI providers connected
- **WHEN** the user has an OpenAI API key and has also connected ChatGPT
- **THEN** the Providers table shows "OpenAI" and "ChatGPT" as separate rows
- **AND** each can be chosen independently as the default provider

### Requirement: ChatGPT requires Commit+ Pro
Connecting and using ChatGPT SHALL require access to the `aiBringYourOwnKey` feature. When the feature policy is unavailable, the local fallback policy SHALL decide, as it does for other Pro AI providers.

#### Scenario: Free-plan user
- **WHEN** a user without Pro access opens the ChatGPT configuration sheet
- **THEN** sign-in is disabled and the sheet offers Sign In or View Pro

#### Scenario: Pro lapses after connecting
- **WHEN** a connected user loses Pro access
- **THEN** ChatGPT cannot be selected or used for requests
- **AND** the user can still disconnect it

### Requirement: Sign-in uses official OAuth with PKCE
The app SHALL sign in through OpenAI's "Sign in with ChatGPT" authorization in the user's browser, using PKCE (S256) and the redirect URI registered for Commit+. The app SHALL reject a callback whose state does not match the request it started.

#### Scenario: Successful sign-in
- **WHEN** the user clicks "Sign in with ChatGPT" and approves access in the browser
- **THEN** the sheet shows the connected ChatGPT account and plan
- **AND** the provider can be saved

#### Scenario: User cancels in the browser
- **WHEN** the user denies access or closes the browser flow
- **THEN** no tokens are stored and the sheet returns to its signed-out state

#### Scenario: Mismatched callback
- **WHEN** a callback arrives with an unknown or mismatched state
- **THEN** the app ignores it and stores no tokens

### Requirement: Plan usage requires the granted scope
The app SHALL check the scopes in the token response and SHALL treat the connection as unusable unless the plan-usage scope was granted. A valid identity alone SHALL NOT enable requests.

#### Scenario: Scope not granted
- **WHEN** the user signs in but the token response lacks the plan-usage scope
- **THEN** the sheet explains that plan access was not granted
- **AND** the provider cannot be saved

### Requirement: Tokens stay in the Keychain and out of model context
ChatGPT access and refresh tokens SHALL be stored only in this Mac's Keychain, SHALL be refreshed automatically before they expire, and SHALL NOT be logged, synced, or included in any model request content.

#### Scenario: Access token expired
- **WHEN** a request is made after the access token has expired and the refresh token is valid
- **THEN** the app refreshes the token and completes the request without asking the user to sign in

#### Scenario: Refresh rejected
- **WHEN** the refresh token is rejected or revoked
- **THEN** the provider shows "Sign in required" and stores no stale access token

### Requirement: ChatGPT serves the AI features of the OpenAI provider
When ChatGPT is the default provider, commit-message generation, repository chat, the repository agent, and conflict resolution SHALL use the connected plan. The repository agent SHALL keep its existing tool policies, confirmations, and revalidation.

#### Scenario: Agent mutation through ChatGPT
- **WHEN** the repository agent, running on ChatGPT, proposes a repository mutation
- **THEN** the app asks for the same user confirmation as with other agent-capable providers

### Requirement: Plan limits never fall back to paid billing
When the plan allowance or a user-set cap is exhausted, the grant is revoked, or the plan is ineligible, the request SHALL fail with an actionable message and the provider SHALL show as unavailable. The app SHALL NOT switch to another provider or to API billing automatically.

#### Scenario: Weekly cap reached
- **WHEN** OpenAI rejects a request because the plan's usage cap is reached
- **THEN** the request fails with a message that the ChatGPT plan limit is reached
- **AND** no request is sent to any other provider

#### Scenario: Ineligible plan
- **WHEN** the connected account's plan does not include third-party usage
- **THEN** the sheet states which plans are supported
- **AND** the provider cannot be used

### Requirement: User can disconnect ChatGPT
Removing ChatGPT from the Providers table SHALL ask for confirmation, delete its tokens from the Keychain, and remove it from the default-provider picker. If ChatGPT was the default provider, the default SHALL revert to Apple Intelligence, the app's standard fallback provider.

#### Scenario: Disconnect
- **WHEN** the user confirms removing ChatGPT
- **THEN** its tokens are deleted from the Keychain and the row disappears
- **AND** later requests never use the removed connection
