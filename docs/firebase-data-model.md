# Firebase backend: project data audit

This inventory was checked against the app's models, dialogs, stores, cloud codec, photo uploader and license functions. It describes the implemented Firebase backend, not an assumption that production deployment has already happened.

## Storage design

Firebase Authentication handles email Login ID and password. The authenticated UID maps to exactly one shared business through `users/{uid}`. New profiles include the authenticated email and an unverified +91 contact phone number. Passwords are never stored in Firestore. `phoneIndex/{verifiedPhoneDigits}` remains only for legacy verified-phone accounts; email accounts cannot claim it. All devices using that account read the same business; login never revokes another device's tokens.

Firestore stores every business record. Firebase Storage stores photo bytes. Cloud Functions provisions a new hotel with twelve default rooms, handles license/PIN operations, and exposes protected admin hotel-management endpoints. No production import reaches cPanel, the old HTTP API, Flutter Secure Storage, or SharedPreferences business persistence. `HotelDataBuffer` is an in-memory view/edit buffer with no disk implementation or fallback. The only app preference retained in the production dependency graph is the OTP abuse throttle; Firebase Auth manages its sign-in tokens.

| Existing feature/data | Firebase location | Notes |
| --- | --- | --- |
| Owner profile, verified phone, role, account mapping | `users/{uid}` | Owner name comes from signup; passwords are not collected or stored. |
| Verified-phone mapping | `phoneIndex/{digits}` | Created atomically with user/business identity; immutable to clients. |
| Hotel identity | `businesses/{businessId}` | Owner UID, business name, phone, onboarding state, server timestamps. |
| Historical floors | `businesses/{id}/floors/{floorId}` | Read-only legacy records; app no longer creates, queries or filters floors. |
| Rooms, rate, availability, current stay | `businesses/{id}/rooms/{roomId}` | Full room model. Rooms are created directly in the business; no floor reference is required. Historical non-empty `floorId` values remain readable. |
| Current and completed bookings | `businesses/{id}/bookings/{bookingId}` | Guest, dates, room, rates, stay status, payments and charge snapshots. |
| Advance/future bookings | `businesses/{id}/futureBookings/{bookingId}` | Reserved dates, guest details, rate, duration, advance, payment mode, additional guests. |
| Customers, identity and stay history | `businesses/{id}/guests/{guestId}` | Identity fields, stay history, Firebase Storage references, photo hashes/type/size; no image base64 in Firestore. |
| Checkout bills and discounts | `businesses/{id}/bills/{billId}` | Full bill model; stable unique receipt ID. |
| Advances, part payments and checkout receipts | `businesses/{id}/payments/{paymentId}` | Amount, mode, date, room/bill reference, kind/source; stable IDs prevent duplicate retries. |
| Additional charges | `businesses/{id}/extraCharges/{chargeId}` | Charge details and room/bill references; also included in room/bill snapshots. |
| Maintenance/closed room details | `businesses/{id}/closedRooms/{recordId}` | Room, status, fault reason and rent. |
| Hotel expenses | `businesses/{id}/expenses/{expenseId}` | Category, description, amount, payment mode, date and stable expense ID. |
| Hotel details and GST configuration | `businesses/{id}/settings/hotel` | Name, address, phone, registration, GST number/rate, app admin setting. |
| Trial and purchased license | `businesses/{id}/settings/license` | Server-owned trial/expiry/plan/activation; clients cannot create or forge licenses. |
| Hotel initialization | `businesses/{id}/settings/onboarding` | Idempotent marker and roomTemplateVersion; new signup adds 101–106 and 201–206 exactly once. |
| Consistent multi-device reads | `businesses/{id}/settings/sync` | Server revision barrier for related records. |
| PIN inventory and rate limits | `licenseKeys`, `licenseAttempts` | Cloud Functions only; no direct client reads/writes. |

## Complete persisted model fields

Room snapshot:

`roomNumber`, `floorId`, `roomName`, `roomType`, `normalRent`, `status`, `faultReason`, `mobile`, `guestName`, `idNumber`, `guestAddress`, `bookingRate`, `bookingDate`, `bookingTime`, `bookingEndTime`, `checkoutTime`, `days`, `advance`, `paymentMode`, `billNumber`, `applyGst`, `futureBooking`, `futureMobile`, `futureGuestName`, `futureIdNumber`, `futureGuestAddress`, `futureBookingRate`, `futureBookingDate`, `futureBookingEnd`, `futureDays`, `futureAdvance`, `futurePaymentMode`, `charges`, `partPayments`, `extraGuests`, `futureExtraGuests`

Bill snapshot:

`billNumber`, `customerId`, `guestName`, `mobile`, `roomNumber`, `roomType`, `bookingDate`, `bookingTime`, `checkoutTime`, `roomRate`, `bookedDays`, `roomBill`, `charges`, `partPayments`, `extraCharges`, `totalBill`, `discount`, `advance`, `advancePaymentMode`, `balance`, `paymentMode`, `applyGst`

Guest identity: `customerId`, `mobile`, `guestName`, `address`, `idType`, `idNumber`, `stayHistory`; front/back/additional-photo Storage paths, content hashes, content types, byte lengths and presence flags. Additional guests remain attached to the corresponding stay/booking and have separate photo references.

Hotel settings: `hotel_name`, `hotel_address`, `hotel_mobile`, `hotel_registration_number`, `hotel_gst_number`, `hotel_gst_tax_rate`, `hotel_admin_password`. The app admin setting is distinct from Firebase Authentication; email/password is the account credential.

## Photo storage

- Primary guest: `businesses/{businessId}/guests/{guestId}/versions/{sha256}/id_front.jpg` and `id_back.jpg`.
- Additional guest: `businesses/{businessId}/guests/{guestId}/additional/{additionalGuestId}/versions/{sha256}/id_front.jpg` and `id_back.jpg`.
- Historical canonical photo paths remain readable for existing data.
- Only the owning Firebase account or a trusted admin custom claim can read a hotel's photos. Uploads require a valid server trial/license, JPEG content type and a maximum size of 5 MB. An expired activated license cannot authorize uploads.
- Saves wait for photo upload work. An unsuccessful upload remains visibly pending and refresh retries it; it is never reported as a completed photo save.

## Data flow and consistency

Login loads the account mapping and business records from the Firestore server. Device/PHP records are never silently imported. New owners receive rooms 101–106 and 201–206 from one atomic server onboarding transaction. Rooms start available with Standard type and rent 0 (shown as “Set room rent”); owners choose actual rates. Additional rooms can be added directly. Home shows all rooms with compact status counts. Snapshots update other devices; the home refresh button explicitly reloads server data.

Room/stay changes and related bills/payments commit together with version checks. A stale second device cannot overwrite a changed record. Failed writes roll back the temporary edit buffer; there is no offline business-data outbox on disk. Expense/customer/settings saves commit when saved rather than waiting for their containing list dialog to close.

Reports, booking slips, PDF bills and expense reports are derived from the Firebase-backed records. User-requested PDF/JSON exports are downloads, not an alternative backend. Historical cPanel compatibility files remain outside the production app's import graph for legacy tests. A test checks this boundary.

## Existing data and deployment

Existing Firestore records and photos remain readable. All rooms appear together on Home, regardless of any historical floor metadata. New room records omit an empty floorId; no floor selection or listener exists in the production dashboard. Existing local/cPanel data is not erased or uploaded automatically. Migrating it requires a verified source export and UID/business mapping; none has been falsely assumed.

The configured production project is `yankees-hotel-pro`. The current CLI account returns HTTP 403 when listing that project's Firestore databases. Live records, counts, provider configuration and deployment therefore remain unverified. No production database or cPanel data was changed during this audit.

After an account with project access is connected, deploy the reviewed backend:

```sh
firebase deploy --project yankees-hotel-pro --only firestore:rules,storage:rules,functions:initializeEmptyHotel,functions:provisionHotel,functions:redeemHotelPin
```

The PIN function also requires its existing `HOTELPRO_PIN_HMAC_KEY` secret in that project. The deployment must not generate or replace that secret for an existing license inventory.


## Shared admin-panel backend

`adminListHotels` reads this same business collection with bounded pagination. `adminSetHotelEnabled` suspends/resumes an existing hotel and writes `adminAuditLogs` in the same transaction. Only the Firebase Auth custom claim `admin: true` authorizes these calls; a profile document cannot grant admin access. Normal owners remain scoped to their own hotel. Suspended hotels retain reads but Firestore/Storage operational writes are blocked. The future panel can use Firebase Auth and these same Firestore/Storage paths without a separate cPanel database.

The admin UI itself has not been built or deployed. No admin privileges were assigned to any account. The user authorized a full reset on 2026-11-03: all Firestore data, Firebase Auth users and Storage photos. The reset is still pending a verified inventory/backup and project access; no production records have been removed.


Default room seeding runs only for a verified new account with no room documents or operational history and no completed onboarding marker. The marker, trial initialization and twelve deterministic room IDs are committed atomically. Returning sessions, deleted rooms, imported/custom hotels and completed hotels are never replenished automatically. No client-side defaults or local seeds are used.


## Elapsed stay tracking

Check-in (`bookingTime`) and actual checkout (`checkoutTime`) are the source of elapsed stay, displayed as total hours and remaining minutes (e.g. 27 hr 3 min). Active room cards and booking controls refresh their display locally from the saved timestamp; no periodic duration counter is written to Firestore. At checkout, bills, checked-out booking projections and primary/additional guest history also persist `stayDurationMinutes`. Room, history, bill, slip and report/PDF formatting share the same calculation. Actual checkout freezes duration; scheduled bookingEndTime does not stop a stay automatically. Missing start timestamps display an unknown duration, and negative elapsed values clamp to zero.
