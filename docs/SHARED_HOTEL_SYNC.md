# Hotel Pro 1 — shared-owner sync changes

Source: `/Users/raghuwansh/hotel_pro_1`. Changes made on 10 October 2026.

## Checkpoint

Before editing, all source and previously uncommitted/untracked files were archived to
`.checkpoints/hotel-pro-1-before-sync-20261010.tar.gz` (excluding generated build/cache
and Git internals). Original Git index/history was not changed; this repository had
no commits. SHA-256: `e4f2dd8baf447080e9366a1924f1198d95022142e4b29c951b72611ddbfcfdb6`.
The checkpoint is private and ignored by Git because existing source includes private
configuration/signing material. Its checksum is in `.checkpoints/SHA256.txt`.

Verification logs are saved in `docs/validation/`.

## Data identity and legacy paths

- Firebase phone authentication UID resolves `users/{uid}.businessId` first; the
  existing `phoneIndex/{full E.164 digits}` must agree. Existing owner-scoped
  business queries and UID-matching caches provide legacy lookup.
- Lookup failures, foreign ownership, contradictory maps, multiple old businesses
  and returning users with missing mappings stop with an error; they never justify
  generating a new business ID. Only confirmed new Firebase Auth registrations
  may initialize a new mapping. Mapping/user/business creation is transactional.
- Existing `businesses/{businessId}` paths and `CUST-*`/`BILL-*` IDs remain readable.
  New customers use deterministic IDs and new bills/payments/expenses use persisted
  unique IDs. A repeated migration or acknowledgement cannot create a second copy.
- Old PHP identities are `SHA256('hp1_login_' + last10PhoneDigits)` or older PIN hashes.
  This old shared-key API does not authenticate the owner and truncates country codes.
  It is unsuitable as a live source of truth. All PHP PUT/poll/force-overwrite code
  is removed. PIN possession does not authorize importing a hotel.
- PHP-only or unmapped legacy owners require an approved inventory/import before
  rollout. The legacy importer is OFF by default. Do not enable the global
  `REVIEWED_LEGACY_PHP_IMPORT` development flag in a general production build.
  Full-phone/UID/business ownership must be established by an administrator first.
  No live PHP or production Firebase inventory was accessed in this task.

## Sync and conflict behavior

Firestore is the shared source of truth for rooms, active/historical bookings, future
bookings, guests, bills, payments, expenses, hotel settings, closed rooms and charges.
Business-scoped real-time listeners refresh the local cache and dashboard. A periodic
retry also handles missed events/reconnects. Local store key names stay compatible.

A durable UID/business-scoped journal records desired data and the last acknowledged
versions. Only records edited relative to the baseline are sent. Firestore transactions
read the affected versions, check all conflicts, then atomically write related changes.
Local wall clocks do not decide the winner. A different concurrent booking/payment
blocks the entire group, preserves local copies and displays a reviewable conflict.
Uncertain-acknowledgement retries are idempotent and preserve unknown legacy fields.

Room actions keep cloud application paused while their dialogs are open and journal
one complete action afterward. Close the room/control dialog to submit the action.
Offline actions are provisional: wait for `Synced` before treating a booking/payment
as confirmed. The app records payments; it does not run an external payment processor.
Physical cash/UPI receipts need reconciliation when resolving a conflict.

Initial loading shows progress/error/retry. Empty first-run local data never pushes
over populated cloud data. Existing verified owners may reopen their cache offline;
a reinstall/new owner must first restore online. Pending changes are flushed before
remote records replace the cache. Archives remain exportable through the sync chip.
A revision barrier prevents restoring rooms and bills from different committed states.

Initial migrations use stable IDs, duplicate/conflict checks and create-only semantics.
Large imports are chunked under a durable migration marker; other phones cannot load
a partially imported hotel. Interrupted migrations resume on the originating device.
A missing originating device requires an administrator to review the preserved import
and migration marker. Normal actions above 400 mutations stop for reviewed processing.
Financial/history records are never deleted merely because a local list omits them.
Explicit room/current-booking removals and user-confirmed expense removals use conflict-checked soft deletion. Shared hotels block the old destructive Fresh Hotel Start command and request a reviewed archive/reset.

## ID photos and license

Old canonical Storage paths remain readable:
`businesses/{businessId}/guests/{guestId}/id_front.jpg` and `id_back.jpg`, including
`additional/{additionalGuestId}` paths. New uploads use immutable content-version
paths under the same business/guest. Firestore holds their paths/hashes. The durable
photo queue retains bytes and original expected versions; failed uploads/metadata
writes remain queued, and conflicting photo replacements preserve both byte copies.
A fresh device downloads referenced photos; failures show `Photos pending` and retry.
A downloaded JPEG is not repeatedly recompressed/uploaded. No automatic photo cleanup
or public access was added.

`settings/license` stores the permanent trial start and valid existing PIN activation.
Existing local activation can be migrated for the same owner. Reinstall retrieves it;
trial start cannot advance and activation cannot be revoked/deleted by clients.
Activation on an authenticated hotel requires cloud acknowledgement; failures are
retryable. If an old installation was removed before its license ever reached cloud,
the missing historical trial/activation cannot be reconstructed from its UID alone.
Such legacy cases need an administrator's backup/entitlement review.

## Deployment approval and impact — NOT DEPLOYED

Production Firestore/Storage rules and data migrations were not deployed or run.
The rule changes must be reviewed and explicitly approved before production:

1. Owner-constrained legacy business lookup is allowed; foreign/public listing,
   business takeovers and forged UID/business links remain denied.
2. New business-data writes require schema version 3. Old version-2 snapshot clients
   will be denied writes. Coordinate an app upgrade and stop older writers before
   migration; do not roll this out with mixed old/new writers.
3. License reset/revoke/delete, physical business-record deletes and photo deletes
   are denied. Versioned guest-photo paths are permitted only for the business owner.
4. More listeners and versioned photos increase Firestore reads and Storage usage.
5. Export/back up production Firestore, Storage, PHP payloads and license entitlements
   before importing. Audit `users`, `phoneIndex`, owner queries, full phones, legacy
   PHP store keys and existing photo paths. Resolve contradictions without re-keying
   established businesses. Review duplicate legacy payments rather than deleting them.
6. Migrate PHP-only records under their verified existing identity, then enable the
   updated application for a small set of test owners. Keep PHP backups read-only.
   The source changes do not deploy a production migration script automatically.

## Verification

Commands use existing locked Flutter dependencies; app dependencies were not upgraded.

- `flutter analyze --no-pub`: no issues.
- Final related Flutter run: 45 passed. Full run: 51 passed, 1 pre-existing OCR failure (52 total).
- Final local Firebase emulator run: 10 passed.
- Related Flutter tests: cloud codec/policy/auth, photo storage, new shared-sync cases.
- Local Firebase rules tests: `tools/firebase_tests/rules.test.mjs` with
  `firebase.emulator.json`, project `demo-hotel-pro-sync`. These verify rules and SDK
  transaction/listener behavior with simulated owner contexts, not real SMS OTP or
  production Flutter plugins on physical phones.
- Full Flutter run retains a pre-existing failing OCR Aadhaar checksum test. The same
  failure was reproduced from the untouched checkpoint. OCR source was not changed.
- Real Android phones, production OTP/SHA configuration, real deployed rules,
  deployed owner inventories and production photo bytes were not verified.

Run the emulator checks without touching production:

```sh
npm --prefix tools/firebase_tests ci --ignore-scripts
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' firebase emulators:exec --only firestore,storage --project demo-hotel-pro-sync --config firebase.emulator.json 'npm --prefix tools/firebase_tests test'
```

## Two-phone acceptance checklist after approved deployment

Use a test hotel, save a backup, and upgrade both Android phones to the same new build.

1. OTP-login with the same full number on A and B. Wait for loading and `Synced`.
   Room counts, guests, future bookings, bills, expenses and settings must agree.
2. Book/change a room or enter a part payment on A and close the dialog. Wait for
   `Synced`; B must update automatically without logging out.
3. Disconnect B, make an edit, close/reopen the app, reconnect, then verify the
   pending edit reaches A exactly once. Repeat with a conflicting edit on A:
   B must display a conflict, preserve its export, and never silently overwrite A.
4. Attempt different guests in the same room from both phones, and simultaneous
   payments against the same baseline. One conflict-free group may commit; the
   other must remain provisional and require review. Also test separate rooms.
5. Once records and photos are fully synced, reinstall B or use a fresh phone.
   Log in with the same number. Check ID front/back/additional photos, old bills,
   settings, original trial date and activation. Do not uninstall a phone with
   unsynced edits or `Photos pending`.
6. Log in with another test owner. None of the first owner's data/photos should
   appear. Switch back and verify original records and any pending owner-scoped edits.

Design references: [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), [real-time listeners](https://firebase.google.com/docs/firestore/query-data/listen), [offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline).
