# Firebase-only hotel flow

The Android app now uses Firebase without a backend selector and signs in through an email Login ID and password. Login and signup use separate routes and isolated form state, with shared custom fields, colors, and responsive layout. Signup collects owner/hotel names and a +91 contact mobile number; returning logins reuse the Firebase UID/business mapping.

Firestore is the source of hotel records. Device business preferences and the Firestore persistent disk cache are disabled in this mode. Temporary UI edits live in memory and require a confirmed server transaction. Failed writes roll back to the last confirmed state. Firebase Auth retains its own sign-in tokens, and the persistent OTP throttle remains enabled. Login on another device does not revoke existing sessions.

Owners create rooms directly under `businesses/{businessId}/rooms/{roomId}`. Floor creation, selection and listeners have been removed. Historical floor metadata is retained but is not required for room creation or updates. New onboarding starts the server trial and atomically creates rooms 101–106 and 201–206 for a new empty hotel. Returning logins reuse existing data. Existing Firebase rooms/history are preserved. Old device/cPanel records are not automatically imported or erased.

## Production access and deployment — 2026-11-03

The CLI account `yankees.res@gmail.com` can access `yankees-hotel-pro`. Live Firestore database metadata, Firebase Auth provider configuration, deployed rules, and the reported hotel mapping were inspected. Email/password authentication is enabled. The reported hotel owner has a password-provider account and the expected owner/business mapping.

The old live rules dated 2026-09-17 did not include a floors collection, which explains the reported floors-list permission denial. Updated Firestore and Storage rules have now been deployed successfully; the released Firestore source was read back and matches the repository exactly.

The reported hotel has pending onboarding and no license/onboarding settings documents yet. The `initializeEmptyHotel` and `provisionHotel` functions are deployed and were read back as ACTIVE in `asia-south1`. An unauthenticated call to `initializeEmptyHotel` returned HTTP 401 / UNAUTHENTICATED, confirming the endpoint does not accept public onboarding requests. The signed-in owner must restart/login to run onboarding; an end-to-end owner session has not been exercised from the CLI. That inspection preceded the completed reset recorded below. A successful server onboarding call must precede room writes requiring a license.

Use the project account explicitly for subsequent commands:

```sh
firebase deploy --project yankees-hotel-pro --account yankees.res@gmail.com --only firestore:rules,storage
firebase deploy --project yankees-hotel-pro --account yankees.res@gmail.com --only functions:hotel:initializeEmptyHotel,functions:hotel:provisionHotel
```

License/PIN and admin endpoints are a separate deployment scope; do not assume those endpoints are already deployed from the onboarding deployment. The PIN signing secret was created in Secret Manager without printing or storing its value in the repository.

## Validation performed

- Flutter analysis: no issues.
- Complete Flutter suite after the backend audit: 82 tests passed.
- Firebase Auth/Firestore/Storage emulator suites: 18 flow/security tests passed, including shared-device sessions, photo restores, owner isolation, atomic payments and room creation without floors.
- Server onboarding/license/admin emulator suite for the default-room update: 16 tests passed, including exact twelve-room templates, concurrent first logins, preserved existing rooms and unchanged trials on reinstall.
- Android `assembleDebug`: successful.

Live multi-device testing with the password account remains pending. Login on another device does not intentionally revoke existing sessions.


## Full reset completed — 2026-11-03

The user explicitly selected all 11 Firebase Auth accounts, including old accounts, and had authorized the linked Firestore/Storage reset. Before deletion, the complete Auth export (including password hashes), Auth hash configuration, 295 Firestore records, 12 Storage objects and exact photo bytes were saved and hash/size verified in `/Users/amanyadav/HotelProBackups/before-user-reset-20261103T072456Z` (private directory/files).

Deleted: 11 Auth accounts, 295 Firestore records under businesses/users/phoneIndex, and 12 Storage objects. Post-reset reads confirmed zero Auth accounts, zero root documents in those three collections and zero live Storage objects. Historical orphan mapping cleanup was included in the complete backup/reset. Rules, Auth providers, Firebase project configuration, deployed functions and the PIN signing secret remain deployed. New signup/first login invokes the twelve-room onboarding template.

The private backup directory contains a verified backup summary, deletion plan/journal and final reset result. This is a completed reset, not a pending operation.


## Room-only Home update

Floor creation/selection/listeners have been removed from the production app. All room records are shown on Home below four compact status counters. Room creation and updates require the existing owner/license/schema checks but no floor reference. Historical floor documents are read-only. The revised Firestore rules were deployed to `yankees-hotel-pro` and read back to confirm an exact source match. Validation: 105 Flutter tests and 22 Firebase emulator checks passed.
