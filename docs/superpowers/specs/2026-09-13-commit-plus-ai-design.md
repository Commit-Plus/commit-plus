# Commit+ AI managed provider

Date: 2026-09-13
Status: Approved by the user on 2026-09-13; implementation has not started.

## Purpose and agreed scope

Provide Commit+ AI as an additional AI provider for Pro users, alongside existing BYOK and on-device providers. Users do not configure a model, upstream provider, or API key for Commit+ AI. The backend owns those choices.

Commit+ AI appears in Settings and every existing AI provider selector. Only authenticated users with active Pro access can select it. Free and signed-out users see a disabled Pro option. All current AI features, including commit-message generation and Repository AI, share its allowance. Existing providers and their access rules remain unchanged.

Both the $2.99 monthly and $29.99 annual Pro plans receive 500 credits per month. One credit represents $0.003 of model usage cost, for a $1.50 monthly model allowance. Fractional credits are supported. Unused credits expire, there is no rollover or top-up, and exhaustion never creates an overage charge.

## Architecture and ownership

The backend lives in a separately deployable `functions/` package in the private landing-page repository. It uses Firebase Functions, Firebase Auth, Firestore, and server-held provider credentials. Website and function deployments remain independently executable.

The macOS repository owns the Commit+ AI provider implementation and presentation. The existing provider abstraction is extended rather than bypassed. Repository Git tools, local access checks, and mutation confirmations remain on the Mac; the backend performs model inference, including returning tool calls.

| Component | Responsibility |
| --- | --- |
| AI endpoint | Verify identity and Pro entitlement, validate payloads, enforce limits, stream model responses |
| Provider adapters | Normalize DeepSeek and Groq requests, responses, usage, and tool calls |
| Credit service | Monthly periods, atomic reservations, settlement, and available balance |
| Polar synchronization | Deliver credit grant, usage, and expiration events reliably and reconcile totals |
| Allowance endpoint | Return available credits, in-flight reservations, and reset time to the app |

Firestore is authoritative for immediate admission and period accounting. Polar is authoritative for paid subscription state and receives a projection of credit accounting for reporting and reconciliation. The app never authoritatively reports its own usage, balance, customer identity, or Pro status.

This design deliberately retains credit-accounting logic in Firebase. Polar alone cannot enforce concurrent request admission or the agreed monthly lifecycle for annual subscriptions.

## Provider configuration

Backend configuration selects an implemented provider adapter, model, output/context limits, monthly allowance, credit conversion, and versioned model pricing. API keys are stored in Secret Manager and bound only to the functions that need them. Ordinary model/provider configuration can use deployment environment variables; changing those values may require deploying a new function revision.

Each admitted request snapshots its configuration version. Configuration changes affect new requests, not the accounting of requests already admitted. Allowance and conversion changes take effect at a new period boundary, preserving the current period's allocation and conversion rules.

DeepSeek and Groq are the initial adapters. Selecting a supported model via configuration must also select compatible capabilities and a valid pricing entry. Unsupported configurations fail closed. Arbitrary provider compatibility is not promised merely by changing a base URL.

No automatic cross-provider retry is required in the first release. This avoids silently starting additional potentially billable calls after an ambiguous upstream failure.

## Monthly periods

A stable subscription anchor determines AI periods for both billing plans. Calendar-month arithmetic uses UTC and the original anchor day/time. A missing day is clamped to the month's last day without changing the original anchor for later months. Paid entitlement expiration caps usable access.

Each period has an immutable ID, start/end timestamps, allowance, conversion version, consumed units, and reserved units. Period initialization is idempotent. Expired periods cannot authorize new requests. Closed periods retain accounting history.

A scheduled function prepares eligible periods. The request path can initialize the current eligible period using the same transaction, so a delayed schedule does not delay access. Missed months do not accumulate allowances. Duplicate webhooks and scheduler runs cannot grant twice.

Canceling renewal retains access until the paid entitlement ends. An inactive or revoked entitlement prevents new inference calls even if a period has unused credits. Changing monthly versus annual billing must not create a second allowance for an overlapping period.

For users already subscribed at launch, initialize the current period from the existing subscription anchor, grant its full allowance once, and expire it at that period's normal end. Do not retroactively issue credits for prior periods. Multiple qualifying subscriptions do not stack allowances for a single Firebase UID.

## Credit arithmetic and request admission

Store integer accounting subunits using a documented fixed precision, rather than binary floating-point credit balances. Choose sufficient precision to make request-level rounding negligible; do not round every call up to one displayed credit. The precise integer scale is an implementation decision shared by Firebase, Polar events, and the app contract.

Calculate model cost from provider-reported usage and the snapshotted price table. Distinguish input, cached input, output, and any other billable categories supported by that adapter without double counting tokens. Do not rely on the provider returning a dollar cost. Convert cost to credits with the period's conversion rate.

Before inference, reserve a conservative upper bound using validated input size/token accounting and an enforced output limit. Reservations are atomic per user/period. If the remaining balance cannot support the request, reduce the output cap only when the adapter can do so meaningfully; otherwise reject before calling the provider. A simple `balance > 0` check is insufficient.

Implement per-user concurrency/rate limits, request-size limits, and a service-level emergency disable control. Reservation correctness and adapter cost bounds must be validated before claiming the allowance is a hard inference budget; infrastructure and uncertain upstream costs are separate operating costs.

## Request lifecycle and failures

1. Verify the Firebase token and server-side active Pro entitlement.
2. Resolve the user period and pin provider/pricing configuration.
3. Atomically create a request record and reserve units.
4. Call the provider and stream text/tool-call deltas.
5. Persist actual usage, settle consumption against that request's period, and release unused reservation.
6. Atomically persist an outbound Polar event alongside settlement.
7. Deliver the event asynchronously with a stable deduplication identifier.

A request ID is scoped to its UID and validated against its payload fingerprint. Reusing the same ID with different content is rejected. Repeating an admitted request cannot cause another upstream invocation or another debit. An in-progress retry returns status instead of launching a replacement. The implementation must define a minimal, bounded result/status retention contract without retaining repository context in accounting records.

Requests settle in their original period even when they finish after its end. New-period availability is never reduced by old-period work. Each model invocation in a Repository AI conversation is accounted separately.

A definitive pre-inference rejection releases its reservation. Known billable usage can still be charged when a user cancels or loses connectivity. An ambiguous upstream outcome moves to reconciliation; it is neither blindly retried nor assumed free. Reconciliation has a bounded resolution policy: query provider usage when supported; otherwise release unresolved user charges after a configured deadline and record the uncertain cost as an operational expense. Do not charge an unverified maximum to the user.

Crashes after provider completion but before settlement require the same recovery handling. A worker lease expiring is not proof that an upstream request stopped consuming tokens. Durable request states and outbox delivery must survive function termination.

## Polar projection and mandatory sandbox validation

Use a dedicated meter and server-side events tied to Firebase UID through the existing Polar customer mapping. Do not attach an overage metered price. Avoid an additional automatic benefit grant that would double-credit the backend-managed monthly allowance.

Polar documents benefit grants by subscription billing cycle and supports custom grants through negative-value events. Its built-in rollover option does not by itself implement this design's monthly schedule for annual subscriptions.

Before finalizing the integration, validate the exact event schema, unit precision, customer-meter visibility without an overage price, stable event deduplication behavior, and the ability to represent grants, consumption, and expiration. Verify the balance sign and UI presentation from actual API responses rather than inferring them from examples.

For each period, the projected grant minus consumption minus expiration must leave zero unused credit after closure. Delayed old-period settlements require a corresponding expiration adjustment so they do not consume the next period's balance. Deliver dependent accounting events in order and reconcile using acknowledged operations; do not implement reset as an uncoordinated read of a potentially stale Polar balance.

Test that retrying every event produces one logical effect and that grant/expiration/late settlement converge after a simulated outage. Firebase remains authoritative while the Polar projection catches up. If the sandbox cannot support this projection reliably, report the limitation for design review before adopting a different Polar accounting contract.

## App behavior and privacy

Commit+ AI has no editable backend model, provider, or key controls. Existing BYOK selection and key storage remain untouched. The backend enforces entitlement even if a modified client bypasses UI restrictions.

Display available allowance and reset time from the backend. Refresh after inference and when the account/provider surface becomes active. Reserve-aware availability prevents presenting already committed credits as spendable. A balance-fetch error appears as unavailable, not zero or a fresh allowance.

At exhaustion, retain Commit+ AI selection, disable new managed requests, and explain the next reset time. Do not automatically choose another provider. On entitlement loss, retain enough selection context to explain the unavailable option while blocking new managed requests.

Explain that managed AI sends the selected repository context through Commit+ infrastructure to its AI provider. Do not log prompts, diffs, source files, credentials, or full model responses in usage events or routine application logs. Accounting records contain identifiers, model/configuration versions, usage, costs, timestamps, and state.

## Validation and delivery

Backend tests cover concurrent admission, duplicate request IDs, duplicate grant jobs/webhooks, month-end anchors, annual subscriptions, entitlement loss, in-flight period rollover, provider failures, unknown usage, outbox retries, and configuration changes.

Adapter checks cover streaming termination, tool-call serialization, token categories, and output bounds with both providers. Polar sandbox checks cover the full monthly lifecycle and late-event convergence before production integration.

macOS integration must cover every selector and both commit generation and Repository AI. Follow repository verification instructions: build the macOS app, do not launch it, and do not rerun a test suite that crashes during bootstrapping. A build is compilation evidence, not runtime UI validation.

Implementation plans are linked from [the roadmap](../plans/2026-09-13-commit-plus-ai-roadmap.md). Backend and macOS changes use their respective repositories and feature branches. This document does not authorize production deployment or billing configuration changes.

## Sources checked

- [Polar credit benefit](https://polar.sh/docs/features/benefits/credits): subscription-cycle grants and rollover.
- [Polar custom credit grants](https://polar.sh/docs/guides/grant-meter-credits-after-purchase): custom grants through events.
- [Polar event ingestion](https://polar.sh/docs/api-reference/events/ingest): event ingestion and duplicate reporting.
- [Polar credits](https://polar.sh/docs/features/usage-based-billing/credits): credits-only spending and application-owned enforcement.
