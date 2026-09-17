# App Update Release Runbook

This runbook is the operator checklist for publishing a production Commit+ app update through GitHub Releases and the stable Sparkle appcast.

## Release Preconditions

1. Confirm the target release version is represented as a semantic tag like `v1.2.3`.
2. Confirm `MARKETING_VERSION` matches that tag without the leading `v`.
3. Confirm `CURRENT_PROJECT_VERSION` will increase relative to the previous public release.
4. Confirm the GitHub Actions secrets and variables in [app-update-secrets.md](app-update-secrets.md) are present and current.
5. Confirm GitHub Pages is still configured to deploy from GitHub Actions.
6. Confirm the pre-push hook is installed (`git config core.hooksPath .githooks`).

## What The Release Workflow Guarantees

The `Release App Update` workflow in [.github/workflows/release-app-update.yml](../../../.github/workflows/release-app-update.yml) performs the release in this order:

1. Validates the pushed tag format and version alignment.
2. Resolves the pinned Sparkle checkout.
3. Imports signing assets into a temporary keychain.
4. Archives and Developer ID exports a Release `Commit+.app` for macOS.
5. Notarizes the ZIP, staples the app, and rebuilds the ZIP after stapling.
6. Verifies bundle metadata, Sparkle feed configuration, code signing, hardened runtime, Gatekeeper acceptance, and `arm64` architecture.
7. Creates a compressed DMG containing `Commit+.app` and an `Applications` symlink.
8. Notarizes, staples, mounts, and verifies the DMG.
9. Creates a stable GitHub Release and uploads both the ZIP and DMG, replacing both assets safely on retries.
10. Waits until both public release assets are reachable.
11. Generates a signed Sparkle `appcast.xml` from the ZIP only.
12. Publishes the appcast to GitHub Pages.

The appcast is intentionally last. If an earlier step fails, clients should never discover a partially published release.

## Preparing a Release

Use the release preparation script to bump `MARKETING_VERSION`, commit, push to `main`, and create the release tag in one step:

```bash
./scripts/release/prepare-release.sh 1.2.3
```

This guarantees the tag version matches the app's marketing version. Do not create tags manually unless you have already updated `MARKETING_VERSION` in `macgit.xcodeproj/project.pbxproj`.

### Installing the Pre-Push Hook

The repository includes a pre-push hook that blocks mismatched tags. Install it once per clone:

```bash
git config core.hooksPath .githooks
```

If you push a tag like `v1.2.3` while `MARKETING_VERSION` is not `1.2.3`, the push is rejected with a clear error.

## Production Release Checklist

1. Run the preparation script for the target version:

```bash
./scripts/release/prepare-release.sh 1.2.3
```

2. Wait for `Release App Update` to finish successfully in GitHub Actions.
3. Open the GitHub Release for that tag.
Expected result: it is not a draft or prerelease, and it contains both the signed ZIP and notarized DMG.
4. Download the released DMG, open it, drag `Commit+.app` to `/Applications`, and verify Gatekeeper locally:

```bash
spctl --assess --type execute --verbose /path/to/Commit+.app
```

5. Verify the downloaded DMG ticket and Gatekeeper assessment:

```bash
xcrun stapler validate /path/to/Commit+-1.2.3-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose /path/to/Commit+-1.2.3-arm64.dmg
```

6. Confirm the published appcast is reachable:

```bash
curl --fail --silent --show-error --location https://commit-plus.github.io/commit-plus/appcast.xml --output /dev/null
```

7. Inspect the appcast entry and confirm it references the just-published ZIP asset, not the DMG.
8. Use the DMG asset for landing-page and manual-download links; reserve the ZIP for Sparkle updates.
9. Run the controlled-feed checklist in [app-update-e2e.md](app-update-e2e.md) against the release before relying on the production feed rollout.
10. Record the qualified version, build number, release URL, and qualification date in the release notes or team log.

## Rollback Guidance

If publication fails before the appcast changes, fix the workflow issue and rerun from a corrected tag or release process.

If a bad release has already reached the public appcast:

1. Remove or replace the bad appcast entry first so installed clients stop discovering it.
2. If necessary, remove the GitHub Release asset or the GitHub Release itself after the feed no longer points at it.
3. Investigate whether the failure came from signing, notarization, appcast metadata, or runtime behavior discovered during qualification.
4. Publish a corrected release only after the controlled-feed checklist passes again.

## Operational Notes

- `SPARKLE_FEED_URL` in GitHub Actions must stay aligned with `SUFeedURL` in the app bundle metadata.
- The repository stores only the Sparkle public key. Keep the private Ed25519 key in GitHub Actions secrets only.
- The production feed should contain only stable releases that completed the full workflow and qualification steps.
- Treat any mismatch between the release ZIP, DMG, appcast enclosure metadata, and signed app bundle as a release blocker.
