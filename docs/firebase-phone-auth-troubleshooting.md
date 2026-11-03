# Android phone verification fix

The reported log contains two separate failures:

1. Firebase Auth rejected the app verification token (`app-not-authorized`, `Invalid app info in play_integrity_token`). The app identity, installed certificate fingerprints and Firebase console configuration must match.
2. The old application code immediately started a second forced reCAPTCHA request inside the first request's failure callback. Firebase still had a browser verification operation open, producing `reCAPTCHA flow already in progress` and `missing-client-identifier`.

## Code changes

- Removed recursive forced reCAPTCHA retry. Firebase's native SDK owns the verification/fallback flow.
- Explicitly keep phone-auth app verification enabled and force-reCAPTCHA disabled.
- Debounce native callbacks, ignore callbacks from previous requests, and prevent duplicate navigation/error handling.
- Keep the persisted OTP cooldown and Firebase server rate limits.
- Configure Firebase App Check before app startup: debug provider for development builds, Play Integrity for production builds. This is independent of Firebase Auth's phone-number app verification.
- Never hardcode a test OTP or disable phone-auth app verification in production.

## Confirmed local identity

The connected device is `emulator-5554`. The installed APK was pulled read-only and its actual signing certificate was verified:

- Package: `com.hotelpro1.app`
- Project: `yankees-hotel-pro`
- Firebase Android app ID: `1:731313332286:android:b27b800afa2dc084d4716f`
- SHA-1: `19:AF:D0:BA:C7:73:AD:17:E5:15:BB:C7:17:EA:17:09:C2:FD:7A:06`
- SHA-256: `DF:B1:D6:B5:DD:CC:C0:D4:13:AF:8D:04:14:C0:EF:D2:D0:65:C0:17:86:D3:68:D5:43:DB:92:07:55:E6:85:15`

These match the current Gradle signing report. The downloaded `google-services.json` has no Android OAuth SHA-1 entries. This does not prove the live project's current registration state; the CLI cannot list it because project access is denied.

## Firebase setup still needed

In the matching Firebase Android app, register/verify both fingerprints. Play Integrity phone verification needs SHA-256; the reCAPTCHA fallback needs SHA-1 and the API-key restrictions must allow the project's `yankees-hotel-pro.firebaseapp.com` verification domain. Download the refreshed Android config when Firebase changes it.

For development App Check, register the device's generated debug token under App Check → the Android app → Manage debug tokens. Keep that token private. Production builds use the Play Integrity provider and the actual production/Play signing certificate.

Use a Firebase-configured fictional phone number/code for emulator testing. Firebase's Flutter phone-auth documentation limits normal real-number phone sign-in to real devices and web. No real OTP was sent during these changes.

Stop the running app and rebuild/run it after these native-plugin and verification changes. Hot reload cannot replace the native plugin or close an old verification activity.

References:
- https://firebase.google.com/docs/auth/android/phone-auth
- https://firebase.google.com/docs/auth/flutter/phone-auth
- https://firebase.google.com/docs/app-check/flutter/default-providers
