# Spec Delta

## Purpose

Lets a user connect their GitHub Copilot account, on either the free or a paid Copilot plan, as a Commit+ AI provider without supplying an API key.

## ADDED Requirements

### Requirement: Copilot is offered as an addable AI provider
Settings → AI SHALL list GitHub Copilot in the "Add Provider…" menu while it is not connected, and in the Providers table once connected. It SHALL be selectable as the default AI provider only while connected and available.

#### Scenario: Not yet connected
- **WHEN** the user opens Settings → AI and Copilot is not connected
- **THEN** "GitHub Copilot" appears in the "Add Provider…" menu
- **AND** it is not selectable in the default-provider picker

#### Scenario: Connected
- **WHEN** Copilot sign-in has completed
- **THEN** Copilot appears in the Providers table with the signed-in GitHub username and selected model
- **AND** it no longer appears in the "Add Provider…" menu

### Requirement: Copilot is available on every Commit+ plan
Configuring and using the Copilot provider SHALL NOT require Commit+ Pro, and SHALL NOT require a Commit+ account.

#### Scenario: Free plan user adds Copilot
- **WHEN** a signed-out or Free-plan user chooses GitHub Copilot from "Add Provider…"
- **THEN** the sign-in flow starts without a Pro upgrade prompt

### Requirement: Sign-in uses a GitHub device code
The app SHALL sign in to Copilot with GitHub's device authorization flow: it shows the user code, offers to copy it and open the verification page, and completes when GitHub confirms. The user SHALL be able to cancel a pending sign-in.

#### Scenario: Successful sign-in
- **WHEN** the user clicks "Sign in with GitHub" and approves the code on GitHub
- **THEN** the configuration sheet shows the signed-in GitHub username
- **AND** the provider can be saved

#### Scenario: Cancelled sign-in
- **WHEN** the user cancels while the device code is pending
- **THEN** no Copilot connection is stored
- **AND** the sheet returns to its signed-out state

#### Scenario: Account without Copilot access
- **WHEN** sign-in succeeds for a GitHub account that has no Copilot entitlement
- **THEN** the sheet shows that the account has no Copilot access
- **AND** the provider cannot be saved

### Requirement: Copilot credentials stay out of Commit+ storage and model context
The app SHALL NOT store, log, sync, or send to any model a GitHub or Copilot token. Copilot authentication state SHALL remain local to this Mac.

#### Scenario: Settings sync
- **WHEN** settings sync uploads app settings after Copilot is connected
- **THEN** the uploaded document contains no Copilot token or sign-in state

### Requirement: Model choices follow the account's entitlement
The model picker SHALL offer the models the signed-in account can use, and SHALL keep a previously chosen model only while it remains available.

#### Scenario: Free Copilot account
- **WHEN** the signed-in account is on Copilot Free
- **THEN** the picker lists only models available to that account

#### Scenario: Saved model no longer offered
- **WHEN** the saved model is missing from the account's current model list
- **THEN** the provider falls back to the account's default model
- **AND** the sheet indicates the change

### Requirement: Copilot serves existing AI features except the repository agent
When Copilot is the default provider, commit-message generation, repository chat, and conflict resolution SHALL use it. Features that require repository agent tool use SHALL report that Copilot does not support them.

#### Scenario: Generate a commit message
- **WHEN** Copilot is the default provider and the user generates a commit message
- **THEN** the message is produced through the signed-in Copilot account

#### Scenario: Repository agent requested
- **WHEN** a feature needs repository agent tool use and Copilot is the default provider
- **THEN** the app reports that the selected provider does not support the agent, as it does for other non-agent providers

### Requirement: Quota and service failures surface as unavailability
Copilot rate limits, exhausted Copilot Free quota, expired sign-in, and a missing language server SHALL be reported as provider unavailability with an actionable message, and SHALL NOT crash or hang the app.

#### Scenario: Free quota exhausted
- **WHEN** Copilot rejects a request because the account's quota is exhausted
- **THEN** the request fails with a message that the Copilot quota is used up

#### Scenario: Sign-in expired
- **WHEN** Copilot reports the user is no longer signed in
- **THEN** the provider shows "Sign in required" in Settings → AI

#### Scenario: Language server unavailable
- **WHEN** the language server cannot be downloaded or started
- **THEN** the provider is unavailable with a message offering to retry

### Requirement: User can disconnect Copilot
Removing Copilot from the Providers table SHALL ask for confirmation, sign out of Copilot on this Mac, and remove it from the default-provider picker. If Copilot was the default provider, the default SHALL revert to Apple Intelligence, the app's standard fallback provider.

#### Scenario: Remove the default provider
- **WHEN** the user confirms removing Copilot while it is the default provider
- **THEN** Copilot is signed out and removed from the table
- **AND** the default provider changes to the fallback provider
