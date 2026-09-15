# Commit+ AI roadmap

Date: 2026-09-13

Design: [Managed provider specification](../specs/2026-09-13-commit-plus-ai-design.md)

The written specification was approved on 2026-09-13. Phase 0 implementation started on 2026-09-13. Production configuration has not changed.

| Phase | Status | Scope | Exit evidence |
| --- | --- | --- | --- |
| [0: Contract validation](2026-09-13-commit-plus-ai-phase-0-contracts.md) | [completed] | Polar sandbox lifecycle and adapter/accounting contract | Grant, fractional usage, expiration, duplicate events, and late settlements converge correctly without overage billing |
| [1: Backend](2026-09-13-commit-plus-ai-phase-1-backend.md) | [completed] | Firebase inference, periods, reservations, recovery, and Polar outbox in landing-page | Targeted backend and adapter checks pass, including concurrent requests and period rollover |
| [2: macOS](2026-09-13-commit-plus-ai-phase-2-macos.md) | [completed] | Commit+ AI integration across macOS selectors and AI workflows | Provider access and allowance presentation reviewed; macOS build succeeds without launching the app |
| [3: Verification and rollout](2026-09-13-commit-plus-ai-phase-3-verification.md) | [in progress] | Cross-system verification and release preparation | Subscription transitions, exhausted allowance, failures, and monthly/annual periods verified; rollout configuration documented |

Phase 0 establishes the exact Polar contract before Phase 1 depends on it. Phase 2 uses Phase 1's frozen HTTP fixtures. Phase 3 follows both integrations. Each plan identifies repository ownership, validation commands, and feature branches. Execute inline unless the user chooses delegation. Production deployment and billing changes require their own concrete rollout review.

## Current repository constraints

- On 2026-09-14, Phase 0 was fast-forward merged locally into clean `main` in both repositories, as authorized. Phase 1 branches are `codex/commit-plus-ai-backend` (landing-page) and `codex/commit-plus-ai-backend-support` (macgit). No push or deployment occurred.
- Before creating future phase branches, follow macgit's AGENTS.md: each relevant repository must be on clean `main`. Integrate the prior phase through the agreed workflow before creating its successor.
- Existing Firebase functions `createWebSignInToken` and `deleteAccount` belong to macgit. New landing-page functions use the distinct `commit-plus-ai` codebase; preserve existing function names and ownership.
- Firestore rules are maintained in macgit, not landing-page. Use server-only AI collections under `users/{uid}` so existing account deletion can remove them, and verify that deletion recursively removes nested records.
- All paths inside phase plans are relative to their explicitly stated repository roots. This keeps plans usable in a new feature checkout.

## Spec coverage

| Requirement | Plan tasks |
| --- | --- |
| Polar event precision, deduplication, monthly expiration | Phase 0 tasks 2–4; Phase 1 task 6 |
| Annual/monthly anchor, existing customers, no rollover | Phase 1 tasks 2–3 |
| Reservations, concurrent requests, retries, unknown costs | Phase 1 tasks 3–6 |
| Backend-owned provider/model/keys and pricing versions | Phase 0 task 3; Phase 1 tasks 4–5 |
| Pro-only provider, all workflows, unchanged BYOK | Phase 2 tasks 1–4 |
| Credit display, session changes, exhausted state | Phase 2 tasks 2 and 4 |
| Privacy, account deletion, operational disable | Phase 1 tasks 5–7; Phase 3 tasks 1–3 |
| Production readiness without launching the Mac app | Phase 3 tasks 2–4 |

## Phase 0 initial execution evidence (superseded by final verification below)

- Implemented an isolated Node 22 package in landing-page with fixed-point accounting, strict HTTP contracts, synthetic fixtures and a restartable sandbox experiment.
- Local unit tests and build pass; live Polar lifecycle is not yet verified.
- Polar sandbox rejected the synthetic `example.com` customer address with HTTP 422 because the domain does not accept email. Execution awaits a valid sandbox customer email; no customer, product or metered price was created by the rejected requests.
- Detailed implementation/evidence: `landing-page/functions/docs/polar-sandbox-evidence.md`. Keep this phase in progress until lifecycle and replay pass against Polar.

## Phase 1 initial foundation checkpoint (superseded below)

- Implemented monthly credit periods, transactional reservations, local settlement, invocation fencing and stable billing anchors in landing-page.
- Backend build and 23 unit tests, 7 billing projection tests, website TypeScript check and 5 real emulator integration tests pass.
- See `landing-page/functions/docs/backend-verification.md` for exact scope and remaining work. HTTP/provider integration, jobs, deletion/rules support and Polar delivery remain unfinished.
- Phase 0 sandbox lifecycle remains pending; starting independent Phase 1 foundations does not waive that gate.

## Final Phase 0 and Phase 1 verification — 2026-09-14

- Phase 0 live sandbox lifecycle, acknowledgement-loss resume and full event replay passed. A dedicated plus alias of the authorized user email isolated the test from the existing sandbox customer. Final balance is 500,000,000 subunits; no product, price or production billing mutation occurred.
- Phase 1 implements authenticated HTTP inference/allowance/status, DeepSeek/Groq adapters, monthly credit transactions, ordered Polar delivery, recovery/cleanup, stable entitlement refresh and account-deletion fencing.
- 93 automated tests pass: 28 backend unit, 23 backend Auth/Firestore emulator, 8 billing projection, 6 legacy function and 28 rules/admin/deletion emulator tests. Backend and website builds pass; website TypeScript check passes separately.
- Evidence and rollout configuration: `landing-page/functions/docs/backend-verification.md`, `deployment.md`, `polar-sandbox-verified.json`.
- Production remains disabled and undeployed. Live model smoke tests/production secrets are Phase 3 rollout checks. Phase 2 macOS integration is complete; execution evidence follows below.

## Phase 2 execution evidence (2026-09-14)

- Phase 1 was merged locally into `main` in both repositories before creating `codex/commit-plus-ai-macos` from clean macgit `main`.
- Managed provider integration, all five AI protocol methods, session-scoped HTTP/SSE, Pro-only selection and reserve-aware allowance UI are implemented. Shared send/generate availability was audited across Settings, File Status, Commit Sheet, Repository AI and Conflict Merge.
- macOS build and test-target compilation passed without launching Commit+. 22 targeted XCTest cases are authored/compiled, not executed.
- [Verification and Phase 3 handoff](2026-09-13-commit-plus-ai-macos-verification.md) records configuration, coverage and pending runtime/live evidence. The backend base URL remains unset pending deployment verification. No Phase 2 merge, remote push or deployment occurred.

## Phase 3 execution status (2026-09-14)

- Phase 2 was fast-forward merged locally into clean macgit `main` at `13efc39c` as authorized. No remote push or deployment occurred.
- Phase 3 branches are `codex/commit-plus-ai-verification` in landing-page and `codex/commit-plus-ai-release-prep` in macgit, both created from clean local `main`.
- Cross-system verification and rollout preparation are in progress. Production remains disabled until the concrete manifest, provider evidence, rollback procedure, and release review are complete.
