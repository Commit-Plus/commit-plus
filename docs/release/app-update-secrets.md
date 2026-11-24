# App Update Release Secrets

## GitHub Actions secrets

- `MACOS_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for the `.p12`
- `MACOS_KEYCHAIN_PASSWORD`: password for the temporary CI keychain
- `APPSTORE_CONNECT_KEY_ID`: App Store Connect API key ID
- `APPSTORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID
- `APPSTORE_CONNECT_API_KEY_BASE64`: base64-encoded contents of `AuthKey_<KEY_ID>.p8`
- `SPARKLE_ED25519_PRIVATE_KEY`: Sparkle private Ed25519 key text

## GitHub Actions variables

- `SPARKLE_PUBLIC_ED_KEY`: public Sparkle Ed25519 key embedded in the app bundle
- `SPARKLE_FEED_URL`: `https://commit-plus.github.io/commit-plus/appcast.xml`

## One-time setup notes

1. Export the Developer ID Application certificate from Keychain Access as a password-protected `.p12`.
2. Base64-encode the `.p12` and the App Store Connect `.p8` before adding them to GitHub secrets.
3. Keep the Sparkle private key only in GitHub Actions secrets. The repository should contain only the public key.
4. In the repository Pages settings, configure GitHub Pages to deploy from GitHub Actions.
5. `SPARKLE_FEED_URL` must stay aligned with `SUFeedURL` in `macgit.xcodeproj/project.pbxproj`.

## Example encoding commands

```bash
base64 -i developer-id-application.p12 | pbcopy
base64 -i AuthKey_ABC1234567.p8 | pbcopy
```
