# Main app release candidate — 12 October 2026

The main source already contains the shared Firestore journal/listeners and
versioned Storage photo implementation exercised by the isolated LOCAL TEST app.
The local-test patch changes routing, Firebase project, package and build memory
settings only. Those routing/package changes must not be applied to production.

The release candidate is 1.0.7+15, package com.hotelpro1.app. A new guard refuses
to create a license for a returning business when its cloud license is missing.
Only a business positively created in the current session can establish its
first license. An existing malformed trial date also requires recovery review.
Local trial/PIN preferences remain unchanged on either refusal.

Built artifact: `build/rollout/Hotel-Pro-1-1.0.7-15.apk` (release).
APK SHA256: `7ad48738dac9994dc433257489a954a74212c47bab72e2f5348988aff9e71d7a`.
Verified signing certificate SHA256 matches the original owner-phone APK:
`bafcba1c4782d36bfd4d967c50a9b371b76944b87fb770a1308ea0f569b3880d`.
Verified package `com.hotelpro1.app`, version name `1.0.7`, version code `15`.
After the user's subsequent explicit instruction, the APK was installed on
Samsung RZCX60SD5AR using `adb install -r` (update from version 13; no uninstall
or data clear) and Sony QV7711KNCG (no prior main package). Both installs returned
Success; package version 15/1.0.7 was read back on both phones and the main
launcher was opened. LOCAL TEST packages/data were retained. Production rules
or an explicit recovery migration were not deployed by these commands.

Source checkpoint (all current uncommitted source preserved):
`.checkpoints/main-update-20261012/source-before-main-update.tar.gz`
SHA256: `3d0ed2496b45c45b955682e4bfe71e0f52f02da6b4f11e703797a9d76b09662c`.

## Verification

- Flutter analyze: no issues.
- Related Flutter sync/photo/license tests: 48 passed.
- Native LOCAL TEST: Samsung checkout reached the server; after restoring the
  Sony USB reverse routes, room 103 was EMPTY on both phones and the test server.
- Room 103 matched one cloud guest. Both ID photos were downloaded by a separate
  authenticated client and matched their Firestore SHA256 references.
- USB routes disappear when a test phone reconnects. This test transport needs
  route restoration; production Firebase does not use Mac USB reverse routes.
- This is not verification of the new release APK on production or a physical
  reinstall. The known prior OCR checksum test failure remains unresolved.

## Before real hotel installation and rollout

Production rules/recovery migration still require explicit rollout approval.
The later user instruction authorized the two device installations described
above. Obtain a fresh read-only cloud audit and current
offline owner-phone backup before executing the recovery proposal. The prior
audit found deleted history, a colliding guest ID, and no cloud license in either
owner business path. Preserve both guest/photo identities; do not bulk undelete
history or recreate payments. Establish the reviewed original activation/date,
then coordinate both main-app updates and rules under explicit rollout approval.

Until recovery is approved and verified, the main release candidate is not a
drop-in production rollout: the license guard intentionally blocks the affected
returning account instead of silently issuing a new trial.
