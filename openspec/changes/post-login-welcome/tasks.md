# Tasks

## 1. Welcome lifecycle and plan resolution

- [x] 1.1 Add transient welcome coordination to AccountSessionController, scoped to interactive attempts and originating windows; extend AccountSessionControllerTests for success, failure, restoration, device recovery, signout, and stale completion suppression.
- [x] 1.2 Resolve welcome content through existing live entitlement state, with neutral pending/error content; add AccountSessionControllerTests covering Free, Pro, delayed results, cached/default Free, errors, and dismissal before resolution.

## 2. Modal presentation and actions

- [x] 2.1 Add AccountWelcomeSheet with the specified Free, Pro, and neutral copy, accessible dismiss actions, and Upgrade to Pro calling existing pricing navigation; verify pricing success/failure with controller test fakes and inspect that loading stays inside the upgrade button.
- [x] 2.2 Integrate AccountSheet and all AuthenticationSheet presenters, removing premature success dismissal conflicts while preserving required recovery and AI gate continuation; cover pending welcome consumption and recovery precedence in AccountSessionControllerTests and review each host's window ownership.

## 3. Integrated validation

- [x] 3.1 Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AccountSessionControllerTests test`; do not launch or relaunch the app separately. If bootstrapping crashes, do not retry; report it and use an app-only build for compilation evidence if needed.
- [ ] 3.2 Review Free/Pro/neutral welcome layout, keyboard dismissal, pricing navigation, and one-modal behavior in an already-running app when available, without launching or relaunching it. Otherwise record runtime review as unverified; leave this task incomplete until reviewed.
- [x] 3.3 Run `openspec validate post-login-welcome --strict` and `git diff --check`, review the final diff, and report actual validation results and any runtime limitations.
