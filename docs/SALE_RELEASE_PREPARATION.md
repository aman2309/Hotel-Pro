# Hotel Pro 1 — 1.0.8+16 sale preparation

No production deployment, new license issuance or phone install was performed
by this preparation. The release APK alone is not a complete rollout.

## Changes

- New/administrator-reset hotels establish a single cloud trial using server
  time from the immutable business creation/reset timestamp. Both devices read the same date. An ordinary returning account with a
  missing license still requires review. Reinstall never proves a new trial.
- The client cannot forge/remove `dataResetAt`: business creation rejects it
  and owner updates allow only name, phone and updatedAt. Existing Admin-created
  reset markers are retained.
- Fresh setup is marked `setupVersion:1`. It opens an empty room list and skips
  the legacy PHP importer. Existing saved hotel records are archived and require
  review instead of silent re-upload into a reset hotel.
- First-login UI bootstrap waits for the verified new-owner mapping transaction, avoiding a race with Firebase Auth state events.
- OTP requests have a persisted phone-specific 60-second cooldown and an
  in-flight guard shared by login/resend. Server throttle extends the local
  pause to five minutes, without promising when Firebase will unblock SMS.
- Room restores wait for pending-photo bytes to be captured durably, rather
  than for Storage upload retries. Legacy queued bytes are captured before
  replacing local records. Photo network errors remain visible/retryable.
- Invalid Aadhaar checksum candidates are rejected; OCR no longer substitutes
  digits to invent a checksum-valid number. Manual ID verification remains
  necessary.
- Expired trials keep owner reads available but reject cloud hotel writes and photo uploads until server activation.
- Release builds suppress the temporary detailed photo debug probe.
- PIN redemption uses an authenticated `redeemHotelPin` server endpoint instead
  of a client Firestore activation write. The server verifies UID/phone/business,
  rate limits failures, claims a purchaser-bound HMAC key in a transaction, and
  preserves the original trialStart. A successful retry for the same hotel is
  idempotent. Concurrent claim by another hotel fails.
- Old cloud activations remain readable. The main app does not silently upload
  a local activation into cloud; any missing old activation needs Admin review.

## Deployment impact and prerequisites

Use only explicit project `yankees-hotel-pro`; the default `.firebaserc` targets
an unrelated project. Proposed config is `firebase.sale.json`. Do not deploy
until the owner approves the production plan.

Rules apply to ALL accounts in this Firebase project. Versions that write old
schemas or activate by direct client writes will be rejected. Inventory affected
customers first; all must have a supported update/activation path. Do not assume
only the two connected phones are affected. On the two test phones, install
the new main APK without uninstall/data clear, then authenticate one device
at a time. Preserve already activated licenses and existing trial dates.

Before deployment take a fresh production rules backup. Existing recovery copy
is `.checkpoints/rollout-20261010/production/`; use its explicit rollback config
after refreshing it. Backend code and rules must be coordinated: deploy/test the
endpoint before applying rules that forbid direct activation. Existing older
apps cannot use this new endpoint, so their update plan is a prerequisite.

Fresh read-only production backup completed:
`.checkpoints/production-audit-1791822989550/` (rules manifest, source copies,
`firebase.rollback.json`, `ROLLBACK.txt`). Inventory has 9 business documents,
9 user mappings and 8 phone-index documents. These are document counts, not
proof of nine distinct owners or nine supported devices. Installed app versions
for other owners are unknown. A project-wide rule deployment is therefore
blocked pending customer/version inventory and the owner's rollout approval.

Set `HOTELPRO_PIN_HMAC_KEY` in Secret Manager. Issuance tool
`cloud/functions/issue_pin.mjs` requires an explicit verified purchaser UID and
private PIN/HMAC environment variables. It creates keys only and refuses an
existing key. No production keys were issued. Keep the secret stable, protect
seller access, and approve any old-PIN enrollment separately. Never put PINs or
the HMAC key in Git or client code. Billing/region/service-account/Secret Manager
permissions and the callable endpoint must be checked on production. App Check
and production abuse monitoring should be configured before broad public sale.

## Checks and outstanding work

Flutter analyze is clean and the full Flutter suite passed (58 tests), including
the previous OCR failure. Local security tests cover owner isolation, realtime,
offline/reconnect, transaction/payment retries, trial immutability, photo reads,
denied older snapshot writes, and forged reset markers. Server tests cover claim
concurrency, retry idempotence, attempt limits and purchaser binding.

Final local emulator result: 12 rules/sync tests and 3 server activation tests
passed. Logs: `.checkpoints/sale-preparation-20261012/emulator-tests.log`.

Built APK: `build/rollout/Hotel-Pro-1-1.0.8-16.apk` (96.3 MB).
Package `com.hotelpro1.app`, version `1.0.8`, versionCode `16` verified.
APK SHA256: `2ee8df9d8cf18e0ecde1959b0f5b8ce291b6f4a35e916e4ad806ad4eabffc83e`.
Signing certificate SHA256 matched original:
`bafcba1c4782d36bfd4d967c50a9b371b76944b87fb770a1308ea0f569b3880d`.
Do not sell/install this candidate as a working production activation release
before its server endpoint and coordinated rules/issuance are approved and tested.

Not yet verified: actual production OTP/SMS unblock, deployed callable HTTP
activation, current production IAM/Storage rules, physical reinstall/photo
restore, and the new 1.0.8 APK on both real phones. PHP/MySQL cleanup remains
blocked by missing access. Do not import its old records during fresh setup.

Current scope does not constitute payment processing, Play Store approval,
seller billing provisioning or proof of commercial release readiness. Those
external release checks must be completed before selling.

Source checkpoint:
`.checkpoints/sale-preparation-20261012/source-before-sale-work.tar.gz`
SHA256 `f901e5b5902b355b5691b44c9ebbb44737080386d728ac024038ffc958e2e24d`.
