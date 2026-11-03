# Hotel Pro Firebase admin

A separate Flutter web entry point lives at `lib/admin_main.dart`. It shares Poppins, the palette and common controls with the Android app, and uses the same `yankees-hotel-pro` Firebase project. Its build is separate from the mobile/web app build.

## Run and deploy

- Run locally: `flutter run -d chrome -t lib/admin_main.dart`.
- Build: `tools/build_admin.sh` (or pass `--no-pub`).
- Deploy the dedicated admin site: `firebase deploy --only hosting:admin --project yankees-hotel-pro` with the authorized Firebase CLI account.
- Build the hotel Android app as usual with `flutter build apk --debug`. The membership screen now accepts HP license keys.

The admin account is `cloud@admin.com`; credentials are not committed. Access requires the server-managed `admin: true` custom claim. There is no public admin registration. Customer accounts cannot list other hotels or issue keys. Claim changes require an Admin SDK/IAM operation and a fresh login/token.

## Panel

Admin actions use centered desktop-style dialogs for confirmations, license generation, record details and photo previews. These share the common modal content and safe-area handling; Android app bottom sheets are unchanged.

Overview shows totals for the loaded hotels, membership state and current occupancy. Hotels can be searched, filtered, inspected and suspended/resumed. Load-more buttons make the scope of paginated metrics and exports explicit. Each hotel includes account/contact/license details, UTC monthly completed billing/expense analytics and all operational collections (rooms, bookings, future bookings, guests, bills, payments, expenses, closed rooms, extra charges, hotel settings). ID photos are loaded from protected Storage only on request. Password and internal activation fields are redacted.

## Keys

Admins choose 1–1,200 months or 1–100 years, optionally bound to a hotel. A key is displayed for copying/downloading at issuance. Raw keys are not stored or logged. Firebase stores HMAC hashes and a last-four-character hint; server secret remains in Secret Manager. Issuance request IDs make network retries idempotent.

The callable `redeemHotelLicenseKey` checks the authenticated owner, hotel mapping, suspension, key state, hotel binding and attempt lockout in a Firestore transaction. A key redeems once. Same-hotel retry is idempotent, including after later renewals. Expiry adds calendar months from the later of server time, unexpired subscription or remaining trial. Month ends clamp (31 January + one month becomes February’s last day). Existing data and the original trial record remain intact. Unused keys can be revoked; suspension is separate from revoking an unused key. Issuance, redemption and hotel access changes have server audit logs.

Legacy annual PIN callables remain available for already-installed older apps; the new app/panel use license keys.

## Validation

Backend emulator tests cover calendar arithmetic, authorization, hotel binding, replay/concurrent redemption, issuance retries, revocation, trial preservation and analytics. Flutter widget checks cover desktop/mobile admin layouts, key generation and the customer membership screen. Live verification uses the configured admin account to read hotels, records and analytics, issue/revoke a diagnostic key and reject unauthenticated admin access. Existing hotels are not activated or modified by that diagnostic.
