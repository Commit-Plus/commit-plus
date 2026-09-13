# Commit+ AI roadmap

Date: 2026-09-13

Design: [Managed provider specification](../specs/2026-09-13-commit-plus-ai-design.md)

The architecture has been discussed and accepted. The written specification is awaiting review. No implementation or production configuration has started.

| Phase | Status | Scope | Exit evidence |
| --- | --- | --- | --- |
| 0 | [pending] | Polar sandbox lifecycle and adapter/accounting contract | Grant, fractional usage, expiration, duplicate events, and late settlements converge correctly without overage billing |
| 1 | [pending] | Firebase inference, periods, reservations, recovery, and Polar outbox in landing-page | Targeted backend and adapter checks pass, including concurrent requests and period rollover |
| 2 | [pending] | Commit+ AI integration across macOS selectors and AI workflows | Provider access and allowance presentation reviewed; macOS build succeeds without launching the app |
| 3 | [pending] | Cross-system verification and release preparation | Subscription transitions, exhausted allowance, failures, and monthly/annual periods verified; rollout configuration documented |

Per-phase implementation plans and their links will be added after specification review. Phase 0 establishes the exact Polar contract before Phase 1 depends on it. Plans must identify repository ownership, validation commands, and feature branches. Production deployment and billing changes require their own concrete rollout review.
