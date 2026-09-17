# Direct App Update Phase 3: Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a signed, notarized, Sparkle-compatible Apple Silicon release from a version tag, upload the ZIP to GitHub Releases, and deploy the generated `appcast.xml` to GitHub Pages only after the release asset is reachable.

**Architecture:** Keep release work outside the app runtime. The workflow archives the app with Xcode, imports signing material into a temporary keychain, notarizes and staples the app, rebuilds the ZIP after stapling, verifies metadata and Gatekeeper acceptance, builds Sparkle's official `generate_appcast` tool from the pinned package checkout, creates a stable GitHub Release asset URL, and deploys a small GitHub Pages artifact containing `appcast.xml`.

**Tech Stack:** GitHub Actions, zsh scripts, Xcode command-line tools, `notarytool`, `stapler`, `ditto`, GitHub CLI, Sparkle `generate_appcast`, GitHub Pages actions.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## Scope Guard

This phase assumes the production feed URL is intentionally fixed at:

`https://commit-plus.github.io/commit-plus/appcast.xml`

`SUFeedURL` in the app target, `SPARKLE_FEED_URL` in GitHub Actions, and the published Pages artifact must all stay aligned with that value.

## File Structure

- Create `.github/workflows/release-app-update.yml`: tag-triggered workflow for archive, notarization, release upload, appcast generation, and Pages deploy.
- Create `scripts/release/import-signing-assets.sh`: create a temporary keychain, import the Developer ID certificate, and decode the App Store Connect API key.
- Create `scripts/release/build-release-archive.sh`: archive the app, copy the signed app out of the `.xcarchive`, and create the ZIP submitted to notarization.
- Create `scripts/release/notarize-and-staple.sh`: notarize the ZIP, staple the app, validate the staple, and rebuild the ZIP so the shipped artifact includes the stapled app.
- Create `scripts/release/verify-release-metadata.sh`: verify bundle identifiers, versions, feed URL, `arm64`, signatures, notarization, and Gatekeeper acceptance.
- Create `scripts/release/generate-appcast.sh`: build Sparkle's `generate_appcast` from the pinned package checkout and emit `appcast.xml`.
- Create `docs/release/app-update-secrets.md`: exact secret and variable inventory for GitHub Actions setup.

## Required Secrets And Variables

Document and use these exact names:

- GitHub Actions secrets:
  - `MACOS_CERTIFICATE_P12_BASE64`
  - `MACOS_CERTIFICATE_PASSWORD`
  - `MACOS_KEYCHAIN_PASSWORD`
  - `APPSTORE_CONNECT_KEY_ID`
  - `APPSTORE_CONNECT_ISSUER_ID`
  - `APPSTORE_CONNECT_API_KEY_BASE64`
  - `SPARKLE_ED25519_PRIVATE_KEY`
- GitHub Actions variables:
  - `SPARKLE_PUBLIC_ED_KEY`
  - `SPARKLE_FEED_URL`

`SPARKLE_FEED_URL` must equal `https://commit-plus.github.io/commit-plus/appcast.xml`.

## Task 1: Add Release Script Scaffolding And Secrets Documentation

**Files:**
- Create: `docs/release/app-update-secrets.md`
- Create: `scripts/release/import-signing-assets.sh`
- Create: `scripts/release/build-release-archive.sh`
- Create: `scripts/release/verify-release-metadata.sh`

- [x] **Step 1: Write the secrets inventory**
- [x] **Step 2: Create the signing import helper**
- [x] **Step 3: Create the archive-and-zip helper**
- [x] **Step 4: Create the release verification helper**
- [x] **Step 5: Run script syntax checks and argument smoke checks**

Verification used during implementation:

```bash
chmod +x scripts/release/*.sh
zsh -n scripts/release/import-signing-assets.sh \
  scripts/release/build-release-archive.sh \
  scripts/release/notarize-and-staple.sh \
  scripts/release/verify-release-metadata.sh \
  scripts/release/generate-appcast.sh
scripts/release/build-release-archive.sh
```

Expected: syntax passes; the final command fails immediately because required arguments are missing.

## Task 2: Add Notarization And Appcast Generation Helpers

**Files:**
- Create: `scripts/release/notarize-and-staple.sh`
- Create: `scripts/release/generate-appcast.sh`

- [x] **Step 6: Create the notarization helper**
- [x] **Step 7: Create the appcast generation helper**
- [x] **Step 8: Run helper syntax checks and argument smoke checks**

Verification used during implementation:

```bash
scripts/release/generate-appcast.sh
```

Expected: non-zero exit because required arguments are missing.

## Task 3: Add The Release Workflow

**Files:**
- Create: `.github/workflows/release-app-update.yml`

- [x] **Step 9: Create the workflow**
- [x] **Step 10: Add a workflow lint smoke check**

Workflow behavior:

- tag trigger: `v*`
- validate semantic version against `MARKETING_VERSION`
- resolve package dependencies into `$RUNNER_TEMP/SourcePackages`
- import signing material into a temporary keychain
- run the full macOS test suite
- archive the Release app and package the notarization ZIP
- notarize, staple, validate, and re-zip
- verify bundle metadata, feed URL, Developer ID authority, `arm64`, and Gatekeeper acceptance
- create a stable GitHub Release with the ZIP
- wait until the public release asset is reachable
- generate `appcast.xml` with Sparkle `generate_appcast`
- upload a Pages artifact containing `appcast.xml` and a small `index.html`
- deploy that artifact through GitHub Pages

Verification used during implementation:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release-app-update.yml"); puts "workflow yaml ok"'
```

Expected: `workflow yaml ok`

## Task 4: Self-Review And Commit

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-app-update-phase-3-release-automation.md`
- Modify: `docs/superpowers/plans/2026-06-27-app-update-roadmap.md`

- [x] **Step 11: Confirm the implementation covers the approved spec**
- [x] **Step 12: Mark Phase 3 complete in the roadmap after fresh verification**
- [x] **Step 13: Commit the phase work**

Checklist for completion:

```text
- signed and notarized arm64 zip
- Sparkle appcast generation using Ed25519 private key
- GitHub Release asset verified before appcast deployment
- GitHub Pages hosting for the feed
- explicit secret inventory
- feed URL alignment with SUFeedURL
```
