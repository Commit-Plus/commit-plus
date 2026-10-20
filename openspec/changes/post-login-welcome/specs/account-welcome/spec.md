# Spec Delta

## Purpose

Confirm successful interactive account authentication and provide welcome actions appropriate to the user's resolved account plan.

## ADDED Requirements

### Requirement: Interactive authentication success confirmation
The app SHALL show one welcome modal in the originating window after successful interactive authentication and required device activation. It SHALL NOT show welcome for failed or cancelled authentication, session restoration, or background refresh.

#### Scenario: Successful login
- **WHEN** email, Google, or web login completes successfully
- **THEN** the login modal transitions to welcome in its originating window without duplicate sheets

#### Scenario: Signup or account linking
- **WHEN** interactive signup or account linking completes successfully
- **THEN** the user receives the same plan-aware welcome

#### Scenario: Device recovery
- **WHEN** login requires device recovery
- **THEN** welcome waits until activation succeeds and is omitted if recovery is cancelled

#### Scenario: Restored session
- **WHEN** the app restores an existing authenticated session or refreshes its account state
- **THEN** no welcome is presented

### Requirement: Plan-aware welcome
The app SHALL display Free or Pro welcome content only after resolving the current account's entitlement. It SHALL NOT interpret an initial default entitlement or stale cache as confirmed Free. Unavailable entitlement SHALL yield a dismissible neutral success message without an upgrade prompt.

#### Scenario: Free account
- **WHEN** the current account is confirmed Free
- **THEN** welcome displays “Welcome to Commit+”, an invitation to explore new and exclusive Pro features, “Upgrade to Pro”, and “Get Started”

#### Scenario: Pro account
- **WHEN** the current entitlement grants Pro access
- **THEN** welcome displays “Welcome to Commit+ Pro”, a message inviting the user to enjoy Pro features, and “Let’s Go”, without an upgrade prompt

#### Scenario: Delayed or failed entitlement
- **WHEN** entitlement is pending or fails to resolve
- **THEN** a neutral signed-in confirmation remains dismissible and never falsely labels the user Free

### Requirement: Welcome actions and lifecycle
The app SHALL allow dismissal without purchase and open the existing pricing destination for Upgrade to Pro. It SHALL preserve authentication, settings-sync recovery, and device recovery behavior, and discard pending welcome when the user signs out or switches accounts.

#### Scenario: Upgrade
- **WHEN** a Free user selects Upgrade to Pro
- **THEN** the app opens pricing using the existing authenticated web flow and reports any failure with a retryable, dismissible welcome

#### Scenario: Continue
- **WHEN** the user selects Get Started, Let’s Go, or closes welcome
- **THEN** welcome closes while the user stays signed in and it does not reappear for the same authentication

#### Scenario: Competing modal or stale result
- **WHEN** settings recovery needs a modal or the account changes while entitlement is resolving
- **THEN** mandatory recovery is preserved, welcome is not presented concurrently, and results for a previous account cannot present welcome
