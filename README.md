# Hotel Pro

Hotel management app with a Firebase backend: email Login ID + password authentication, owner-scoped Firestore records, Firebase Storage for ID photos, and Cloud Functions for twelve-room onboarding and licensing.

The production app has no backend selector and cannot import the cPanel API or device business-data persistence. All hotel records come from Firebase. Edits remain in memory only until the server confirms them; there is no disk-backed business-data fallback. PDF/JSON exports are explicit downloads, not backend storage.

The app supports the same account on multiple devices, live updates, direct room creation without floors, and a home refresh button.

- [Complete data audit and Firebase schema](docs/firebase-data-model.md)
- [Deployment status and setup](docs/firebase-cutover.md)

The configured Firebase project is `yankees-hotel-pro`. Production deployment/data inspection is currently pending an authorized Firebase account; the current CLI account returns HTTP 403. Local emulator validation does not imply production deployment.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Firebase rules, Auth, Storage, onboarding and license tests are in `tools/firebase_tests` and `cloud/functions`. Use Firebase emulators with a `demo-` project for those tests.

The PHP/cPanel files and historical compatibility tests are retained for reference and migration only. They are not dependencies of the production app and are not deployed by the Firebase configuration.


Account login uses Firebase Email/Password. Enable **Authentication → Sign-in method → Email/Password** in `yankees-hotel-pro`, then deploy the updated Firestore rules and Cloud Functions. Signup creates the owner/hotel mapping and returns to login; login never creates an account. Passwords are managed by Firebase Auth and are never stored in Firestore. Mobile is a +91 contact number, not a verified login identity. Unknown-account errors invite signup; privacy-protected invalid-credential errors mention both incorrect credentials and signup. Existing phone-only accounts need an explicit account migration before password login; this change does not silently create or merge identities.

New hotel accounts receive 12 available Standard rooms (101–106 and 201–206) during server onboarding. Default rent is unset (0); owners set actual rates. Seeding is atomic and runs once, so returning logins preserve room edits and deletions.
