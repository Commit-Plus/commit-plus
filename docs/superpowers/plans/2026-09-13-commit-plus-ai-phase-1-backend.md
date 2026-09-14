# Commit+ AI Phase 1: Firebase Backend Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not delegate unless the user chooses delegation.

**Goal:** Implement authenticated managed inference with a 500-credit monthly allowance, bounded reservations, durable settlement, and the validated Polar projection.

**Architecture:** An independently deployed `commit-plus-ai` Firebase codebase in landing-page calls DeepSeek/Groq. Firestore owns immediate accounting; a durable, ordered outbox projects that accounting into Polar. Existing website billing remains the subscription integration entry point.

**Tech Stack:** Node 22, TypeScript, Firebase Functions v2, Firebase Admin, Firestore transactions, native fetch/SSE, Polar SDK, Node test runner, Firebase emulators.

---

## Completion status — 2026-09-14

**[completed] Implementation and local/sandbox verification.** No production deployment or live model enablement.

| Task | Delivered outcome | Status |
| --- | --- | --- |
| 1 | Codebase ownership, records, emulator setup, deployment guide | completed |
| 2 | Shared billing projection, stable anchor, paid-end/freshness checks and refresh | completed |
| 3 | Monthly periods, reservations, pricing snapshots and bounded maintenance | completed |
| 4 | DeepSeek/Groq adapter profiles, streaming/usage/tool validation and bounds | completed |
| 5 | Firebase-authenticated inference/allowance/status and runtime disable | completed |
| 6 | Ordered outbox, settlement/corrections, recovery and retention | completed |
| 7 | Rules coverage, recursive account deletion, builds and 93 passing tests | completed |

Implementation consolidations: provider differences live in one `providers/chat.ts` with reviewed profiles rather than duplicated adapters; settlement/correction live in `credits/service.ts`; `commitPlusAIMaintenance` combines bounded idempotent jobs. Queries use only single-field indexes, documented with their exact shapes. Legacy rules already deny new paths, so tests were extended without broadening rules. Account deletion retains a minimal fence permanently to reject late work.

The billing projection is shared with the website. Its test compiler uses ESNext/Bundler and relative-extension rewriting (`pnpm test:ai`) because the original NodeNext recipe conflicts with the website's CommonJS package boundary and Turbopack. Actual website build and a separate no-emit type check pass. The checklist below is the original execution recipe; this completion table and `landing-page/functions/docs/backend-verification.md` record the delivered outcomes and actual commands rather than claiming the recipe's exact historical commit/test order.

Live Polar lifecycle/replay is verified. No live LLM call was made: production provider credentials/smoke tests remain a Phase 3 gate. Conservative full-context reservations are explicitly documented; old ambiguous Polar sends stop for reconciliation instead of assuming unlimited dedup retention.

## Prerequisites and execution roots

- Phase 0's signed-event lifecycle must pass in Polar sandbox before implementing the outbox against it. Use its versioned HTTP fixtures without independently redefining them.
- Primary root: `/Users/thanhtran/Project/Commit+/landing-page`; branch `codex/commit-plus-ai-backend` from clean `main` after Phase 0 is integrated.
- Companion root: `/Users/thanhtran/Project/Commit+/macgit`; branch `codex/commit-plus-ai-backend-support` from clean `main` after documentation is integrated. Companion scope is Firebase rules, existing deletion function, and deployment ownership only.
- Follow the clean-main rule before creating either branch. Current planning branches are not implementation bases. Resolve branch prerequisites with the user when execution starts.
- Run commands from the stated repository root. The `functions/` package and scripts are created by Phase 0. Run `rtk pnpm --dir functions test` after each backend task; do not use a Next.js build as TypeScript evidence because the website ignores build-time type errors.

## Task 1: Define persistent records and deploy ownership

**Create in landing-page:** `firebase.json`, `functions/src/index.ts`, `functions/src/store/records.ts`, `functions/src/store/firebase.ts`, `functions/src/store-records.test.ts`, `functions/docs/deployment.md`.
**Modify in macgit:** `firebase.json` only if deployment inventory confirms an explicit legacy codebase annotation is needed. Do not rename deployed functions blindly.

- [ ] Define server-only paths under each user: `aiState/current`, `aiPeriods/{periodID}`, `aiRequests/{requestID}`, `aiRequestIDs/{requestID}`, `aiOutbox/{operationID}`. Keep the existing `entitlements/{uid}` document's current fields compatible with the macOS decoder.
- [ ] Use these record invariants in `store/records.ts`; validate safe integers at every Firestore boundary:

```ts
export type RequestState = 'reserved' | 'invoking' | 'settled' | 'released' | 'reconciling';
export interface PeriodCounters {
  allowanceUnits: number;
  consumedUnits: number;
  reservedUnits: number;
}
export function availableUnits(p: PeriodCounters): number {
  const values = [p.allowanceUnits, p.consumedUnits, p.reservedUnits];
  if (!values.every(v => Number.isSafeInteger(v) && v >= 0)) {
    throw new RangeError('Invalid credit counters');
  }
  const result = p.allowanceUnits - p.consumedUnits - p.reservedUnits;
  if (result < 0) throw new RangeError('Credit counters exceed allowance');
  return result;
}
```

- [ ] Write a Node test importing `availableUnits`, asserting `{allowanceUnits: 500_000_000, consumedUnits: 100_000, reservedUnits: 3_000_000}` yields `496_900_000`; assert a reservation exceeding allowance throws. Run it red before adding the implementation, then green.
- [ ] Add immutable period start/end, conversion version and grant ID. Request records contain UID-scoped ID, HMAC payload fingerprint, period/config IDs, reservation, lease and invocation timestamps, state, actual usage, and settlement ID. Tombstones contain request ID/fingerprint and terminal state but no source content. Outbox records contain sequence, stable event ID, signed units, period, attempt count, and acknowledgement state.
- [ ] Configure landing-page `firebase.json` with functions `source: "functions"`, `codebase: "commit-plus-ai"` and a predeploy package build. Leave Firestore rules deployment owned by macgit. Add Firestore/Auth emulator configuration using a `demo-commit-plus-ai` project; emulator tests must never fall back to production.
- [ ] Inventory existing function ownership read-only before choosing any legacy annotation. New production deploy commands must target `functions:commit-plus-ai`; never use a broad deploy that could delete `createWebSignInToken` or `deleteAccount`. Record the exact observed legacy ownership in deployment documentation.
- [ ] Build and test the package. Commit explicit files with `rtk git commit -m 'feat: scaffold isolated managed AI backend records'` after staging only this task's paths.

## Task 2: Extend billing synchronization with a stable AI anchor

**Modify in landing-page:** `lib/polar.ts` (`PolarEntitlementSubscription`, `applyPolarSubscriptions`, customer/subscription synchronization paths).
**Create:** `lib/ai-entitlement.ts`, `tests/ai-entitlement.test.ts`, `tests/tsconfig.ai.json`, `functions/src/billing/entitlement.ts`, `functions/src/entitlement.test.ts`.
**Modify:** `.gitignore` to exclude `tests/.compiled/`.

- [ ] Extend the subscription projection to include verified subscription ID, Polar customer ID, and `startedAt`/`currentPeriodStart`. Preserve the existing `billingUpdatedAt` stale-event guard and device-limit reconciliation. Do not make user-provided timestamps authoritative.
- [ ] Keep one stable anchor in `users/{uid}/aiState/current`. For existing customers choose the effective active subscription's non-null `startedAt`, falling back to verified `currentPeriodStart`; do not use `createdAt` blindly when it precedes activation. Preserve the anchor across uninterrupted upgrades and monthly/annual switches. A returning subscription after an actual access gap may establish a new anchor only without overlapping grants.
- [ ] Before applying AI eligibility, obtain the complete active subscription set when a single-subscription webhook could mask another active subscription. Do not let canceling one of several subscriptions revoke another valid Pro grant; do not stack allowances. Keep existing account entitlement behavior unchanged except for an explicitly tested correction needed to compute this authoritative set.
- [ ] Export a pure eligibility projection from `lib/ai-entitlement.ts` and test active annual, canceled-but-paid, revoked, stale update, multiple active subscriptions, missing anchor, and billing-plan switch. Missing verified anchor or expired paid access must prevent AI admission rather than initialize from the request date.
- [ ] Implement the function-side read against server-owned records. Treat plan/access/paid-end as separate fields, and verify all three. Reconcile subscription state on cache expiry (initial maximum age five minutes, configurable) and fail closed on an expired verification cache when Polar is unavailable. Fresh verified entitlement can continue during a transient Polar projection outage.
- [ ] Define and test the trial decision: trialing receives AI only when it belongs to the existing product's active Pro entitlement contract; do not create a new trial allowance product or per-request grants. If production trials exist but do not carry paid Pro access, exclude them using verified entitlement rather than status alone.
- [ ] Keep `lib/ai-entitlement.ts` pure, without Next.js aliases or Firebase initialization. Set `tests/tsconfig.ai.json` to NodeNext module/moduleResolution, ES2022 target, strict mode, esModuleInterop, rootDir `..`, outDir `.compiled`, and include only `ai-entitlement.test.ts` and `../lib/ai-entitlement.ts`. Test imports use `../lib/ai-entitlement.js`. Run `rtk pnpm exec tsc -p tests/tsconfig.ai.json`, then `rtk proxy node --test tests/.compiled/tests/ai-entitlement.test.js`. Expect exit 0 and no failed tests. Run backend tests separately; do not claim `pnpm build` proves the website's types are valid.

## Task 3: Implement month arithmetic, initialization, and reservations

**Create:** `functions/src/credits/period.ts`, `functions/src/credits/service.ts`, `functions/src/credits/pricing.ts`, `functions/src/period.test.ts`, `functions/src/reservations.emulator.ts`, `functions/src/pricing.test.ts`.

- [ ] Write this concrete month-end regression before implementing the UTC boundary function:

```ts
import assert from 'node:assert/strict';
import test from 'node:test';
import { boundary } from './credits/period.js';

test('month-end clamping does not drift the original anchor', () => {
  const anchor = new Date('2028-01-31T08:00:00.000Z');
  assert.equal(boundary(anchor, 1).toISOString(), '2028-02-29T08:00:00.000Z');
  assert.equal(boundary(anchor, 2).toISOString(), '2028-03-31T08:00:00.000Z');
});
```

- [ ] Implement `boundary(anchor: Date, offset: number)` by constructing the target UTC year/month at day 1, finding its last day with day 0 of the following month, and setting `min(originalDay, lastDay)` plus the original UTC time. Reject invalid dates and noninteger offsets. Resolve the current interval using the anchor, never by adding a month to a previously clamped boundary.
- [ ] In a transaction read entitlement, state and period before writing. Create only the current period, one grant event and immutable conversion snapshot. Initial allocation is 500,000,000 units. Existing Pro users get that current allocation once; missed periods are not backfilled. Close previous periods and emit exact expiration adjustments. Enforce paid-end on every admission.
- [ ] Add a schedule and request-path initializer calling the same service. Page eligible users with a persisted cursor and bounded batch size; catch up on a delayed schedule without scanning all historical periods or issuing past grants. Use timestamps/queries that have documented indexes.
- [ ] Implement `reserve` as one Firestore transaction that checks request tombstone/fingerprint, active entitlement, period, concurrency, rate window and available units, then creates the request and increments reservation. Initial rate defaults: one active inference per UID, 30 new invocations per rolling minute; duplicates consume neither rate allowance nor another reservation. Store rate policy in backend config.
- [ ] Add emulator concurrency tests: two 300-credit reservations against 500 credits permit exactly one; retrying the accepted ID leaves counters unchanged; reusing it with different content returns conflict; changing UID cannot read or resume it. Same-UID concurrency and credit rejection have distinct error codes.
- [ ] Add a separate `test:emulator` package script, `pnpm run build && node --test lib/*.emulator.js`, and the emulator config described in Task 7 before running the transaction suite. Pure suites stay `*.test.ts`; emulator suites end in `.emulator.ts`. Thus ordinary `pnpm test` remains offline and never accidentally accesses Firestore.
- [ ] Use fixed decimal/BigInt calculations for pricing. Sum noncached input, cached input and output independently; reasoning included in output must not be billed twice. Round only at the subunit boundary. Test `$0.0003 -> 100,000 units` and `$0.003 -> 1,000,000 units`, configuration rollover, negative usage and unsafe numeric inputs.
- [ ] Record pricing snapshots and available credit after each transaction. Run emulator tests and commit the credit service only after concurrency and month-boundary cases pass.

## Task 4: Implement bounded provider adapters

**Create:** `functions/src/providers/types.ts`, `functions/src/providers/deepseek.ts`, `functions/src/providers/groq.ts`, `functions/src/providers/sse.ts`, `functions/src/config.ts`, `functions/src/providers.test.ts`, `functions/src/sse.test.ts`.

- [ ] Define an adapter interface around Phase 0's messages/tools, an output token cap, `AbortSignal`, delta callback, and a final response containing text, complete tool calls and normalized usage. The adapter also returns an input-token upper bound and maximum billable units for reservation. Never accept model or API key overrides from HTTP payloads.
- [ ] Use this normalized usage type to avoid overlapping input categories:

```ts
export interface Usage {
  uncachedInputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
}
```

- [ ] Test cached tokens are subtracted from total prompt tokens exactly once, missing usage is marked unknown, negative/noninteger usage is rejected, and an interrupted SSE frame is not treated as a final response. Test JSON frames split at every byte boundary, Unicode split across chunks, CRLF, comments, multiple data lines and the provider terminal marker.
- [ ] Implement an incremental UTF-8/SSE parser with bounded frame size. Accumulate tool arguments by call index/ID, then validate complete JSON only at terminal completion. Never dispatch tools on the backend.
- [ ] Select reviewed models/prices from Phase 0 evidence. Use a verified tokenizer/upper-bound policy that includes role framing, tool schemas and hidden billable categories; a character-count heuristic is not a guaranteed upper bound. If no supported bound exists, disable that model until one is established. A fallback may reserve the documented maximum billable input for the model, but must not claim useful small-request economics without measuring it.
- [ ] Set output caps server-side per operation: initial targets are 250 tokens for commit messages and 3,000 for repository responses; agent/conflict caps must be declared in config and validated against selected model capability. Cap thinking/reasoning where supported and include its billable tokens. Disable unsupported reasoning modes rather than letting provider defaults escape the reservation.
- [ ] Bind only required provider secrets through Firebase Secret Manager. Add config validation for provider enum, model/pricing match, safe limits, price version, and emergency disable. No automatic fallback/retry after an ambiguous upstream send. Run adapter fixtures for both providers; real-provider smoke tests remain a separate, explicitly recorded check.

## Task 5: Expose authenticated inference, allowance and request status

**Create:** `functions/src/http/auth.ts`, `functions/src/http/routes.ts`, `functions/src/http/validation.ts`, `functions/src/inference/service.ts`, `functions/src/inference.test.ts`, `functions/src/http.test.ts`.
**Modify:** `functions/src/index.ts`.

- [ ] Export `commitPlusAI` using `onRequest` from `firebase-functions/v2/https`. Use explicit timeout, region, max instances and per-instance concurrency; keep response handling awaited until settlement/outbox persistence or a durable reconciling state has been recorded. Do not fire-and-forget work after the response.
- [ ] Verify Firebase ID tokens and account revocation policy. Route identity comes only from token UID. Enforce the Phase 0 schema and maximum decoded body size (initial 256 KiB); reject unknown keys and oversize payloads before reserving credits. Do not log request bodies or bearer tokens.
- [ ] Bind the three Phase 0 routes and stable error schema. Allowance/status reads are UID-scoped. Free users receive `pro_required`; duplicate in-progress IDs receive 409 and status location. No stored full model output means completed retries return status, not reconstructed text.
- [ ] Use a two-step invocation state transition: transactionally reserve, then mark `invoking` before sending to the provider. A crash before `invoking` can safely release; a crash after that state requires reconciliation. Fence leases with an invocation owner/version so a worker retry cannot submit an already-invoking request again.
- [ ] Stream provider deltas with backpressure. On disconnect, abort upstream promptly, record any received usage and settle or reconcile; do not equate cancellation with zero cost. `completed` is emitted only after durable settlement; accounting-pending uses its own terminal status.
- [ ] Verify the emergency disable before admission and immediately before invocation. Accept no new calls when disabled; existing calls settle normally. If actual provider billing exceeds a proven reservation, record a cost-bound violation, stop further managed admission for that configuration and account for the excess as operational cost rather than creating a negative user balance.
- [ ] Test expired token, other-UID request lookup, Free access, missing Pro anchor, zero balance, duplicate IDs before/after completion, provider 4xx, upstream timeout, client disconnect and kill switch. Fixtures must assert provider invocation count, not only HTTP status.

## Task 6: Settlement, outbox and recovery

**Create:** `functions/src/credits/settlement.ts`, `functions/src/polar/outbox.ts`, `functions/src/jobs/recovery.ts`, `functions/src/jobs/periods.ts`, `functions/src/settlement.test.ts`, `functions/src/outbox.test.ts`, `functions/src/recovery.test.ts`.
**Modify:** `functions/src/index.ts`.

- [ ] Settle exactly once in a transaction: decrement request reservation, increment actual consumption, record terminal state/tombstone, and create a stable usage event. In a closed period also create the matching expiration correction; new-period counters do not change. Repeating settlement with the same result is a no-op; a differing result is reconciled as a new explicit correction.
- [ ] Deliver one UID's outbox in sequence with a fenced worker lease. Use the exact event deduplication contract proven in Phase 0. On timeout retain the original ID/body and retry only within verified semantics. Acknowledgement is durable before advancing the cursor. Mark missing/deleted Polar customers as terminal attention conditions, not retry loops that recreate accounts.
- [ ] Test the full signed sequence: `-500, +20, +480, -500, +3, -3` credits. It must converge to 500 available in the current period even with duplicated delivery and a timeout between the final two events. Temporary Polar divergence is allowed; Firebase admission remains correct. Publish no success report until all operations are acknowledged.
- [ ] Add a recovery scan for stale invoking/reconciling requests. Wait beyond the configured upstream deadline before recovery; expired lease alone does not prove the upstream call ended. Query provider usage only when the adapter has a supported request-usage lookup. Otherwise retain pending state for an initial 24-hour reconciliation window, then release the user reservation and classify unknown provider cost as operational expense.
- [ ] Rate-limit repeated ambiguous outcomes per UID/configuration so cancellation cannot create unlimited uncharged requests. Preserve known billable usage, and make the recovery deadline/rate policies server-configured. Never charge the reserved maximum as if it were measured usage.
- [ ] Add jobs for outbox delivery, period catch-up and metadata cleanup. Retain request metadata 90 days and compact ID tombstones for the account lifetime; no source/result data is persisted. Record collection-group indexes in `functions/docs/deployment.md` with the exact query using each index.
- [ ] Execute emulator failure injection at reserve, invoking, provider completion, settlement, send and acknowledgement boundaries. Expect one upstream invocation per accepted ID and one logical Polar effect per accounting operation. Commit after tests converge.

## Task 7: Firestore rules, account deletion and package verification

**Modify in macgit:** `firestore.rules`, `firebase-tests/firestore.rules.test.mjs`, `functions/src/index.ts`, `functions/src/index.test.ts`.
**Create in landing-page:** `functions/firebase.test.json`, `functions/docs/backend-verification.md`.

- [ ] Verify new `users/{uid}/ai*` paths are denied for all client reads/writes, including their owner; app allowance is available only through the authenticated endpoint. Add explicit rule tests for all five collections and cross-UID access. Do not broaden the existing settings/device rules.
- [ ] Extend `deleteAccountData` with the five AI collections using its existing dependency injection seam. Set a server-only deletion fence before deleting the Polar customer; admission and workers must honor it, so no outbox can recreate a removed account or settlement can resurrect removed records. Make retries idempotent and retain the fence until in-flight work is fenced off. Verify the deletion helper actually removes nested records, then test every new collection path.
- [ ] Use a fake provider and a dedicated emulator project. `functions/firebase.test.json` configures Auth/Firestore ports and emulator-only indexes/rules; tests must reject execution without `FIRESTORE_EMULATOR_HOST`. Run:

```sh
rtk pnpm --dir functions exec firebase emulators:exec --config firebase.test.json --project demo-commit-plus-ai --only auth,firestore 'pnpm run test:emulator'
```

Pin `firebase-tools` as a functions dev dependency before using that command; because `--dir functions` changes the execution directory, the config path is package-relative. Do not use production project `macgit` for emulator fixtures.
- [ ] In macgit run `rtk npm --prefix functions test` for the existing deletion function. Run rule tests with `rtk proxy firebase emulators:exec --project demo-commit-plus-ai --only firestore 'npm --prefix firebase-tests test'` after the test harness is confirmed to use the emulator project ID. In landing-page run `rtk pnpm --dir functions test` and `rtk pnpm --dir functions build`. Run `rtk pnpm exec tsc --noEmit` for website billing edits, reporting pre-existing failures distinctly.
- [ ] Inspect `rtk proxy git diff --check` in each repository, capture actual results in the verification document, and mark Phase 1 complete only after all required contract/emulator checks pass. No production deploy in this phase.

## Sources and dependency contract

- [Multi-repository Firebase codebases](https://firebase.google.com/docs/functions/organize-functions)
- [Firebase secret configuration](https://firebase.google.com/docs/functions/config-env)
- Use Phase 0 evidence for exact Polar semantics and current provider usage fields; do not infer those from an OpenAI-compatible label.
