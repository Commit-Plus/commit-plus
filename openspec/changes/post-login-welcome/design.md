# Design

## Context

See proposal.md for motivation. AuthenticationSheet dismisses on account UID, and AccountSessionController.completeAuthentication also clears presentedSheet. Settings and AI gate presenters have additional dismissal observers. Entitlement observation begins after authentication and resets to .free before a live value arrives. Device recovery and session restoration share completion code. Existing AccountSessionControllerTests provide injected authentication and entitlement fakes.

## Goals / Non-Goals

**Goals:** Coordinate a single, correctly scoped welcome with verified plan content and existing modal lifecycles.

**Non-Goals:** Change billing, plan feature gates, Firebase contracts, or startup onboarding. No new backend writes, policies, or deployment are required.

## Decisions

1. AccountSessionController owns a transient interactive-authentication intent, originating window, account UID, and pending welcome state. Distinguish interactive attempts from restoreInitialDeviceSession; keep intent across successful device recovery and clear it on cancellation, signout, and superseding attempts. Avoid triggering on any authenticated state transition, which would also affect restoration.
2. Use existing AccountSheet/replacingSheet routing and a dedicated presentation-only AccountWelcomeSheet. Audit AuthenticationSheet, ContentView, AccountSettingsView, ConnectionsSettingsView, AIProvidersSettingsView, and AICommitMessageLoginRequiredSheet so local presenters hand off cleanly before controller presentation. Capture the initiating window before asynchronous work; never redirect to whichever window happens to be key later. Avoid independent welcome state in each presenter because it can produce duplicate sheets.
3. Use the existing entitlement provider and AccountEntitlement.hasProAccess. A live observation or load for the matching UID resolves content; initial .free and cached values are not confirmation. Present neutral success immediately while pending, update within that same modal on resolution, and keep neutral content on failure. A dismissed welcome must never reopen on a delayed result. No new plan feature key is introduced; existing policy fallback and gates remain unchanged.
4. Free copy: “Welcome to Commit+” / “You’re signed in and ready to go. Upgrade to Pro to explore new and exclusive features and get more from Commit+.” Actions: “Upgrade to Pro” and “Get Started”. Pro copy: “Welcome to Commit+ Pro” / “You’re all set. Enjoy your Pro features, and make your next commit a great one.” Action: “Let’s Go”. Neutral copy confirms sign-in without asserting a plan, with “Get Started”. Use a compact native sheet, a success symbol, centered copy, accessible button labels, and no standalone spinner between actions.
5. Upgrade calls openPricingOnWeb, reusing .pricing and existing web errors. Show opening state inside its button and prevent repeated requests. Keep welcome available for retry or dismissal if opening fails; do not imply purchase occurred.
6. Mandatory settings conflict/device recovery takes priority. Queue welcome until required recovery and dismissal complete; preserve existing sync decisions and AI gate continuation, allowing them to resume after welcome. Welcome dismissal consumes only this interactive attempt.

## Risks / Trade-offs

- Multiple local presenters and UID observers can dismiss too early → audit every AuthenticationSheet host and controller presentation branch.
- Entitlement arrives late or for a previous user → key resolution to account UID and interactive attempt, with neutral fallback.
- Settings sync may compete for the same sheet → explicitly serialize required recovery and welcome.
- App bootstrapping may block XCTest or UI review → report the limitation without relaunching or retrying Firebase crashes.

## Migration Plan

Ship as a native client update with no persisted state migration. Roll back the welcome routing and view together if needed. No Firebase deployment or pricing-page modification is planned.
