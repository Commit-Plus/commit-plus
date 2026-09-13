# Commit+ AI roadmap

Date: 2026-09-13

Design: [Managed provider specification](../specs/2026-09-13-commit-plus-ai-design.md)

The written specification was approved on 2026-09-13. Implementation plans are ready; no implementation or production configuration has started.

| Phase | Status | Scope | Exit evidence |
| --- | --- | --- | --- |
| [0: Contract validation](2026-09-13-commit-plus-ai-phase-0-contracts.md) | [pending] | Polar sandbox lifecycle and adapter/accounting contract | Grant, fractional usage, expiration, duplicate events, and late settlements converge correctly without overage billing |
| [1: Backend](2026-09-13-commit-plus-ai-phase-1-backend.md) | [pending] | Firebase inference, periods, reservations, recovery, and Polar outbox in landing-page | Targeted backend and adapter checks pass, including concurrent requests and period rollover |
| [2: macOS](2026-09-13-commit-plus-ai-phase-2-macos.md) | [pending] | Commit+ AI integration across macOS selectors and AI workflows | Provider access and allowance presentation reviewed; macOS build succeeds without launching the app |
| [3: Verification and rollout](2026-09-13-commit-plus-ai-phase-3-verification.md) | [pending] | Cross-system verification and release preparation | Subscription transitions, exhausted allowance, failures, and monthly/annual periods verified; rollout configuration documented |

Phase 0 establishes the exact Polar contract before Phase 1 depends on it. Phase 2 uses Phase 1's frozen HTTP fixtures. Phase 3 follows both integrations. Each plan identifies repository ownership, validation commands, and feature branches. Execute inline unless the user chooses delegation. Production deployment and billing changes require their own concrete rollout review.

## Current repository constraints

- macgit is clean on `codex/commit-plus-ai-design`; landing-page is clean on `release` as inspected on 2026-09-13.
- Continue documentation work on the existing design branch. Before creating implementation branches, follow macgit's AGENTS.md: each relevant repository must be on clean `main`. Ask the user to switch/integrate existing branches at that point; do not silently branch phase work from the current branches.
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
