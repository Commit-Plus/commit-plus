# Proposal

## Why

Successful login currently dismisses the authentication modal without a visible confirmation, leaving users unsure whether it worked. A welcome modal should acknowledge success and offer an appropriate next step for their plan.

## What Changes

- Show a welcome modal after successful interactive authentication, including email, Google, web callback, signup, and account linking.
- For confirmed Free accounts, show “Welcome to Commit+” with an optional invitation to discover new and exclusive Pro features, an “Upgrade to Pro” action opening pricing, and “Get Started” to dismiss.
- For Pro accounts, welcome them to Commit+ Pro, invite them to enjoy their Pro features, and offer “Let’s Go”.
- Resolve the current account’s plan before displaying plan-specific content; use a neutral success state if it cannot be resolved.
- Show once per interactive authentication, after device activation succeeds, never for background session restoration.

## Capabilities

### New Capabilities
- `account-welcome`: Plan-aware confirmation and next steps after interactive account authentication.

### Modified Capabilities
None.

## Impact

AccountSessionController, AuthenticationSheet, account sheet routing and authentication presenters, a focused welcome view, and AccountSessionControllerTests. Reuse existing entitlement and pricing navigation services. No Firebase schema, policy, pricing, or backend changes are intended.
