# Commit+ AI Phase 0: Contract Validation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use subagents only if the user explicitly chooses that execution method.

**Goal:** Produce a reproducible Polar sandbox experiment and freeze the accounting and inference contracts before production backend work.

**Architecture:** An isolated TypeScript package runs pure accounting tests and an opt-in Polar sandbox experiment. No deployed AI endpoint, production billing mutation, or real repository context is needed.

**Tech Stack:** Node.js 22, TypeScript, Node test runner, pnpm, Polar SDK 0.47.1 with `Polar-Version: 2026-04` as already used by landing-page.

---

## Ownership and prerequisites

Implementation root: `/Users/thanhtran/Project/Commit+/landing-page`. Documentation root: `/Users/thanhtran/Project/Commit+/macgit`.

Branch after the clean-main prerequisite: `codex/commit-plus-ai-contracts`. The planning snapshot has landing-page on `release`; do not switch or create a phase branch without resolving that prerequisite with the user. Phase work and sandbox execution are not performed while merely writing this plan.

Use a dedicated sandbox customer/meter and environment-provided sandbox credentials. If unavailable, finish local tests and the runnable experiment, then report that live sandbox evidence is missing. Never substitute production credentials or invent a successful sandbox result.

## Task 1: Isolate the package and its test commands

**Create:** `functions/package.json`, `functions/pnpm-lock.yaml`, `functions/tsconfig.json`, `functions/.gitignore`, `functions/src/contracts.test.ts`.
**Modify:** root `tsconfig.json` to exclude `functions` from the Next.js compilation; retain other exclusions.

- [x] Create a private package using Node 22, ESM, `src` as TypeScript root, and `lib` as output. Reuse already installed version choices for `firebase-admin` (13.10.0), `firebase-functions` (7.2.5), TypeScript (6.0.3), and Polar SDK (0.47.1); pin direct versions and generate the package's own lockfile. Do not alter root dependency versions or introduce a root pnpm workspace migration.
- [x] Define the package scripts exactly as follows. Keep test files directly in `src` so the glob covers every suite:

```json
{
  "build": "tsc -p tsconfig.json",
  "test": "pnpm run build && node --test lib/*.test.js",
  "sandbox:polar": "pnpm run build && node lib/experiments/polar-lifecycle.js"
}
```

- [x] Ignore `node_modules/`, `lib/`, `.env*`, and private experiment output; allow a redacted `.env.example`. Install with `rtk pnpm --dir functions install`.
- [ ] Add the accounting test in Task 2, then run `rtk pnpm --dir functions test`. Expect an initial missing-module failure before creating the accounting module. Do not treat dependency/bootstrap failure as a meaningful red test.

## Task 2: Define precision and a closed-period projection

**Create:** `functions/src/accounting.ts`, `functions/src/contracts.test.ts`, `functions/docs/ai-contract-v1.md`.

- [x] Define 1,000,000 integer subunits per displayed credit. A 500-credit grant is 500,000,000 units; 1 unit represents $0.000000003 at the initial conversion. Calculate provider cost using BigInt/fixed decimal arithmetic, convert only checked safe integers at the Firestore/JSON boundary, and preserve conversion versions.
- [x] Write and run this concrete regression test before implementing `projection`:

```ts
import assert from 'node:assert/strict';
import test from 'node:test';
import { projection } from './accounting.js';

test('late consumption leaves a closed period at zero', () => {
  const grant = 500_000_000;
  const before = projection(grant, 20_000_000, true);
  const after = projection(grant, 23_000_000, true);
  assert.equal(before.expiration, 480_000_000);
  assert.equal(after.expiration, 477_000_000);
  assert.equal(3_000_000 + after.expiration - before.expiration, 0);
  assert.equal(after.net, 0);
});
```

- [x] Implement the pure projection with explicit validation:

```ts
export function projection(grant: number, used: number, closed: boolean) {
  if (![grant, used].every(Number.isSafeInteger) || grant < 0 || used < 0 || used > grant) {
    throw new RangeError('Invalid period accounting');
  }
  const expiration = closed ? grant - used : 0;
  return { expiration, net: -grant + used + expiration };
}
```

- [x] Add assertions for an open period, a fully consumed period, zero usage, and invalid/unsafe integers. Run `rtk pnpm --dir functions test`; expect all assertions to pass.
- [x] Document logical operations: grant `-G`, consumption `+U`, expiration `+(G-U)`. After closing, a late usage delta `+D` is accompanied by expiration correction `-D`. This expresses an accounting projection, not an assumption about the sign of Polar's displayed balance.

## Task 3: Build and run the sandbox experiment

**Create:** `functions/src/experiments/polar-lifecycle.ts`, `functions/src/polar/client.ts`, `functions/src/polar/events.ts`, `functions/src/polar-events.test.ts`, `functions/.env.example`, `functions/docs/polar-sandbox-evidence.md`.

- [x] Read the installed SDK declaration `node_modules/@polar-sh/sdk/dist/esm/models/components/eventcreateexternalcustomer.d.ts` and the current official API. The inspected SDK exposes both `externalId` and `externalCustomerId`; use the former for stable event identity and the latter for the Firebase UID mapping. Do not confuse the two.
- [x] Test the event encoder with the following exact contract (the function is exported from `polar/events.ts`):

```ts
const event = accountingEvent('sandbox-user', 'period-1:grant', -500_000_000);
assert.deepEqual(event, {
  name: 'commit_plus_ai_accounting',
  externalCustomerId: 'sandbox-user',
  externalId: 'period-1:grant',
  metadata: { units: -500_000_000, schema_version: 1 }
});
```

- [x] Implement `accountingEvent(uid: string, id: string, units: number)` as that exact object after checking nonempty IDs and safe integer units. Initialize `Polar` with `server: 'sandbox'` and the existing version-header hook. The experiment rejects any environment setting requesting production and never prints tokens or full HTTP headers.
- [ ] Provision one dedicated sandbox customer, a Sum meter filtered to `commit_plus_ai_accounting`, and no overage price. Record whether a credits benefit/product association is necessary for customer-meter visibility. If one is necessary, test a zero automatic allocation; do not introduce a second 500-credit benefit.
- [ ] Execute sequentially with stable IDs: grant 500 credits; consume 0.1 credit; resend the same usage event; consume another 19.9 credits; expire 480 credits; grant the next 500; settle 3 credits in the old period with the matching -3-credit expiration correction. Poll for convergence with a bounded timeout, at most 60 seconds per tool wait, and readable progress updates.
- [ ] Simulate a delivery timeout and restart using the same IDs. Assert one logical effect for each event and a final new-period available balance of 500 credits. Verify SDK/API sign, raw integer precision, duplicate responses, and customer-meter visibility. Record mismatches as failures.
- [ ] Run `rtk pnpm --dir functions sandbox:polar` only after dedicated sandbox variables are available. Save a redacted evidence table with API version, IDs masked where appropriate, expected/actual deltas, deduplication results, timestamps, and exit status. Record the actual API limit on duplicate identity retention if documented; otherwise design reconciliation to stop ambiguous replays rather than assuming indefinite deduplication.
- [ ] If the signed event/expiration contract fails, stop dependent integration and present the concrete failed scenario. Do not quietly replace Polar credit accounting with a different product design.

## Task 4: Freeze HTTP and adapter contracts

**Create:** `functions/docs/ai-contract-v1.md`, `functions/src/contracts.ts`, `functions/fixtures/commit-request.json`, `functions/fixtures/agent-response.sse`, `functions/fixtures/errors.json`.

- [x] Define `POST /v1/inference`, `GET /v1/allowance`, and `GET /v1/requests/:requestID` under one `commitPlusAI` HTTP function. All routes require a Firebase bearer token; the request ID is a UUID and account identity is obtained from the token.
- [x] Freeze this JSON shape; server validation rejects unknown provider, model, key, token-count, and cost overrides:

```json
{
  "version": 1,
  "requestID": "f019f2fc-6a66-460e-a377-0c53f194c950",
  "operation": "repository_agent",
  "responseFormat": "text",
  "messages": [{ "role": "user", "content": "Explain the supplied diff." }],
  "tools": [],
  "stream": true
}
```

- [x] Enumerate operations `commit_message`, `repository_response`, `repository_agent`, and `conflict_resolution`, plus `responseFormat` values `text` and `json_object`. The server validates the allowed operation/format pair and adapter capability; this field cannot select a model or change the pricing policy. Messages permit system/user/assistant/tool roles, tool-call IDs and JSON tool arguments; tools permit only function schemas. Reject remote tool execution URLs, binary inputs, and provider-specific built-in tools in v1.
- [x] Specify SSE events `text_delta`, `tool_call_delta`, `completed`, and `error`. `completed` includes full final text/tool calls plus settled allowance; clients never execute partial tool arguments. If usage is unresolved, return a typed pending-accounting status instead of claiming settlement. Before streaming use HTTP 401/403/409/413/422/429/503; after streaming begins emit typed `error` without pretending to change HTTP status.
- [x] Freeze allowance fields: `periodID`, `periodStart`, `periodEnd`, `resetsAt` (nullable when access ends), `allowanceUnits`, `consumedUnits`, `reservedUnits`, `availableUnits`, `unitsPerCredit`, `access`, and `accountingPending`. Dates use ISO 8601 UTC. Error codes include `pro_required`, `credits_exhausted`, `request_in_progress`, `request_already_completed`, `request_id_conflict`, `rate_limited`, `provider_unavailable`, and `accounting_pending`.
- [ ] Persist request metadata for 90 days without context/result text. Request-status responses do not replay model output; completed retries return `request_already_completed`. Validate newly admitted UUID creation time is not available from UUIDv4, so instead retain compact consumed-ID tombstones for the account lifetime to prevent an old ID becoming billable again after metadata retention. Account deletion removes tombstones too.
- [ ] For each configured DeepSeek/Groq model, record official supported streaming, tools, output limit and usage categories. Use synthetic text for provider smoke checks, only when test keys and execution authorization exist. Without a safe input-token upper bound or output billing bound, that model stays disabled. Do not hardcode a model name or price from old memory.
- [ ] Run local tests/build, review the redacted sandbox evidence, and commit only the explicit package/documentation files on the phase branch. Update roadmap Phase 0 to completed only with passing live sandbox evidence and frozen fixtures.

## Sources

- https://polar.sh/docs/api-reference/events/ingest
- https://polar.sh/docs/features/benefits/credits
- https://polar.sh/docs/guides/grant-meter-credits-after-purchase
- https://api-docs.deepseek.com/api/create-chat-completion/
- https://console.groq.com/docs/api-reference

## Execution checkpoint — 2026-09-13

Implemented in `landing-page/functions` on `codex/commit-plus-ai-contracts`. The arithmetic regression was added before implementation; the first compile also exposed a TypeScript 6 `types: ["node"]` bootstrap requirement, which was corrected. A later missing-contract-module red test was verified before the parser implementation. Node 22.23.2 local verification passes.

The live experiment requires `POLAR_SANDBOX_CUSTOMER_EMAIL`; example.com was rejected by Polar email validation before any resource creation. A valid email was requested from the user. Grant, expiration, lost-acknowledgement resume, and full replay remain unchecked until live evidence exists. Provider readiness is documented with both candidates disabled; no provider key or LLM smoke request is part of the completed evidence.
