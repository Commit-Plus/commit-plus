# Firebase Setup

Commit+ keeps Firebase configuration local. The app remains usable in guest mode when the configuration file is absent.

## Firebase project

1. Create or select the Firebase project used by Commit+.
2. Register an Apple app with bundle ID `dev.thanhtran.macgit`.
3. In Firebase Authentication, enable:
   - Email/Password.
   - Google.
4. Do not enable email verification as an application requirement for the Firebase foundation phases.
5. Create a Cloud Firestore database. Deploy Firestore rules from the private `landing-page` repository before using production data.

## Google OAuth client

Google Sign-In on macOS uses an OAuth client whose application type is **iOS**.

1. Open Google Cloud Console for the same project.
2. Create or verify an iOS OAuth client with bundle ID `dev.thanhtran.macgit`.
3. Return to Firebase Authentication, verify Google remains enabled, and download a fresh `GoogleService-Info.plist`.
4. Confirm the downloaded file contains `CLIENT_ID` and `REVERSED_CLIENT_ID`.

## Local app configuration

1. Save the downloaded file at:

   ```text
   macgit/GoogleService-Info.plist
   ```

2. Do not commit this file. The path is ignored by Git.
3. Add the plist's `REVERSED_CLIENT_ID` as a URL scheme for the `macgit` target before enabling the Phase 1 Google sign-in flow.
4. Never print `API_KEY`, OAuth client IDs, or Firebase tokens in test logs.

`FirebaseBootstrap` looks for `GoogleService-Info.plist` in the application bundle. If it is absent or invalid, bootstrap reports `missingConfiguration` and Commit+ continues in guest mode.

## Backend source and deployment

Firestore rules, Cloud Functions, emulator tests, and operator scripts are maintained in the private `landing-page` repository. See that repository's `docs/firebase-backend.md` for installation, testing, and deployment commands. Historical plans in this repository use the paths that existed when they were written.

The macOS app still connects directly to the same Firebase project through the Firebase SDK. Auth, Firestore listeners, local caching, and callable function names are unchanged.

## Settings sync

Settings sync is optional and device-local. It starts when a Free or Pro user is signed in and enables **Sync Settings** on that Mac. Guest workflows remain fully local, and entitlement changes do not pause cloud observation or uploads.

The first time a Mac finds different local and cloud values, Commit+ asks whether to use the cloud values or keep that Mac's values. Canceling this choice disables sync on that device. After the initial choice, local changes are debounced and remote changes apply without being uploaded back as echoes.

The only synchronized values are:

- Toolbar button text visibility.
- Submodule visibility.
- Subtree visibility.

Firestore stores these values at `users/{uid}/settings/app`. The document must contain exactly `schemaVersion`, the three boolean settings, and the server timestamp `updatedAt`. Repository state, credentials, Git history, and other preferences are never included.

## Validation

Check required local keys without printing their values:

```bash
for key in BUNDLE_ID PROJECT_ID GOOGLE_APP_ID CLIENT_ID REVERSED_CLIENT_ID IS_SIGNIN_ENABLED; do
  /usr/libexec/PlistBuddy -c "Print :$key" macgit/GoogleService-Info.plist >/dev/null
done
```

The `BUNDLE_ID` value must equal `dev.thanhtran.macgit` and `IS_SIGNIN_ENABLED` must be `true`.
