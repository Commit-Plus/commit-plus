# Commit+ AI Phase 3: Verification and Rollout Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. No delegation unless chosen by the user.

**Goal:** Verify the complete managed-AI lifecycle and prepare an evidence-backed rollout without accidentally changing production billing or launching the macOS app.

**Architecture:** Exercise a dedicated sandbox Firebase/Polar environment with synthetic inference and real contract adapters as separately authorized. Keep operational controls and deployment manifests in the private backend repository; record macOS compilation and unexecuted runtime checks honestly.

**Tech Stack:** Existing phase test packages, Firebase emulators, Polar sandbox, provider fixtures, xcodebuild, a versioned deployment runbook.

---

## Roots, prerequisites and phase status

Backend root: `/Users/thanhtran/Project/Commit+/landing-page`; branch `codex/commit-plus-ai-verification` from clean `main` after Phase 1 integration. macOS documentation/necessary fixes use `codex/commit-plus-ai-release-prep` from clean `main` after Phase 2 integration. Follow the repository branch prerequisite before creating either.

Inputs are Phase 0's live evidence and frozen contract, Phase 1's emulator evidence, and Phase 2's macOS build result. Missing inputs are explicit incomplete checks, not assumed successes. Production deployments, billing changes and real-provider spending use the execution authorization available at that time; prepare the concrete rollout first before requesting any missing approval.

## Task 1: Cross-system lifecycle fixtures

**Create in landing-page:** `functions/src/lifecycle.emulator.ts`, `functions/src/session-deletion.emulator.ts`, `functions/docs/verification-evidence.md`.

- [ ] Seed two synthetic UIDs in the Auth/Firestore emulators with matching isolated Polar sandbox customers. Use a fake clock and adapter with configurable usage/failure points; never upload real repository context. Keep production credentials out of the fixture environment.
- [ ] Implement each row as an independent named test with exact accounting assertions:

| Scenario | Action | Expected result |
| --- | --- | --- |
| Monthly Pro | Start active subscription, request allowance twice | One 500-credit grant, same period ID |
| Annual Pro | Advance to next monthly boundary within paid year | New 500-credit period, old remainder expired |
| Leap/month end | Jan 31, Feb end, Mar 31 | Original anchor restored in March |
| Existing user | Initialize midway through existing period | One full current grant, no historical grants |
| Multiple subscriptions | Two active Pro subscriptions for one UID | One allowance, no stacking |
| Billing switch | Monthly to annual while access continues | No overlapping second allowance |
| Canceled renewal | Cancel with future paid end | Access until paid end; no grant beyond it |
| Revoked access | Revoke before a new inference | Provider invocation count stays zero |
| Concurrent use | Competing reservations exceed available credit | At most affordable request admitted |
| Duplicate ID | Replay same request and webhook IDs | One invocation/grant/settlement |
| Changed payload | Same ID with a different message | 409 conflict, no extra reservation |
| Month rollover during call | Reserve old period, settle in new month | New period stays at 500 credits |
| Lost upstream usage | Inject unknown completion outcome | Pending, then released by recovery policy; unknown cost tracked separately |
| Outbox outage | Timeout before acknowledgement | Same ID retried; signed projection converges |
| Deleted account | Delete with a pending request/outbox | No resurrection or new Polar customer |
| Other account | Ask for another UID's request status | Denied without disclosing its status |

- [ ] Assert both Firestore counters and ordered signed Polar events. For late settlement, explicitly test the temporary projection divergence and its eventual correction. Do not assert instantaneous Polar balance updates.
- [ ] Run `rtk pnpm --dir functions test` and the Phase 1 emulator command. Re-run the opt-in sandbox lifecycle with the same recorded API version. Save time, command, commit SHA, expected result and actual result per scenario, excluding tokens and content.

## Task 2: Provider and app protocol verification

**Create in landing-page:** `functions/docs/provider-compatibility.md`.
**Update in macgit:** `docs/superpowers/plans/2026-09-13-commit-plus-ai-macos-verification.md`.

- [ ] Compare the backend request/response fixtures byte-for-byte with macOS fixture copies. Check schema version, operations, response format, integer units, null reset dates, errors, terminal SSE and full tool argument assembly. Reject a protocol drift before rollout.
- [ ] For DeepSeek and Groq, validate the configured model's output cap, actual usage mapping, response formats and tool calls against official current documentation and synthetic live calls when credentials/spend are authorized. Record live token counts and calculated charge; do not treat fixture tests as proof of provider behavior.
- [ ] Verify a two-turn agent exchange: first response requests a local tool, the Mac-side harness fixture produces the tool result, and the second inference is a distinct request. Sum both charges. Do not add remote Git execution to make this test easier.
- [ ] Exercise commit-message, plain chat, structured answer, agent turn and conflict-response fixtures. Confirm every output still passes the app's existing semantic decoder; valid transport JSON alone is insufficient.
- [ ] Reuse the successful macOS build from Phase 2 if source/configuration has not changed. If it changed, run the same sequential xcodebuild command once after fixes. Do not launch the app or automatically retry a hosted test crash. Keep UI/hosted test gaps listed for release review.

## Task 3: Prepare concrete deployment and operating controls

**Create/update in landing-page:** `functions/docs/deployment.md`, `functions/docs/operations.md`, `functions/.env.example`.
**Update in macgit:** `docs/firebase-setup.md` only for function ownership/deploy boundaries relevant to the new codebase.

- [ ] Record exact non-secret deployment configuration: project, region, codebase, endpoint URL, config/pricing versions, selected model, credit conversion, allowance, timeouts, request/concurrency limits, recovery deadline and max instances. Document secret names only, never values. Use Secret Manager bindings and service credentials without copying a local service-account JSON into a deployment artifact.
- [ ] Record prerequisite changes in order: Firestore rules/deletion fence and cleanup support; required indexes; website AI entitlement projection; backfill of verified active Pro anchors; isolated AI codebase initially disabled; synthetic allowlisted smoke checks; app endpoint configuration; enabling general managed access after review. No backfill may issue historical monthly credit grants.
- [ ] Inventory the existing functions before/after the proposed deploy. Deployment targets only `functions:commit-plus-ai`. If macgit's legacy codebase needs annotation, include its observed current label and an explicit migration check rather than assuming renaming the local configuration changes ownership safely.
- [ ] Define an operational kill switch checked before admission and invocation. An emergency disable stops new calls while recovery/outbox workers remain enabled to settle existing work. Do not delete accounting collections, reset balances or revoke paid Pro as a rollback action.
- [ ] Document monitoring: request error rate, unknown-cost count, reservation age, outbox oldest pending age, config cost-bound violations, and model cost per user/month. Log structured metadata only. Alert thresholds are configuration values with a named operator action; initial thresholds include any cost-bound violation, outbox age over 15 minutes, and requests pending beyond the 24-hour reconciliation window.
- [ ] Show the worst-case model budget: $1.50 per eligible user/month, $18 for 12 annual allocations, plus infrastructure and unknown operational cost. Include the observed Polar account fee plan rather than assuming Starter pricing. This is a budget estimate, not proof of total spend capped at $1.50.
- [ ] Prepare rollback instructions restoring the prior backend revision/config while preserving period conversion snapshots and request state. Replaying jobs must not grant another allowance. Test rollback against a synthetic in-flight request before describing it as verified.

## Task 4: Final review and handoff

**Update:** the roadmap and all phase verification documents.

- [ ] Run `rtk proxy git diff --check` in each changed repository. Inspect changed files for keys, source-context logging, accidental BYOK policy changes, newly billable Polar prices and broad deploy commands. This is a focused review of the actual change, not a new unrelated security project.
- [ ] Prepare a release-review table listing each evidence item as passed, failed or not executed. Link to actual artifact paths and commit SHAs. Include every missing live provider, sandbox or macOS runtime check instead of silently treating it as passed.
- [ ] Present the concrete deployment manifest, expected functions/Polar changes and rollback instructions for any remaining production approval. Do not ask for blanket permission before the manifest is ready. Do not deploy, push, merge, or modify production billing merely because the design and implementation plan were approved.
- [ ] Commit the completed verification/runbook files on the phase branches. Mark Phase 3 complete when its verification and release-preparation deliverables are complete; track production deployment/publication separately and never claim the feature is live without verifying it.
