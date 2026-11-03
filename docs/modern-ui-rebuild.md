# Modern Hotel Pro UI rebuild

The active app uses the login design's cream, sage and dark-green palette with bundled Poppins. UI callbacks continue to use the Firebase backend; this work did not replace booking, checkout or payment calculations.

## Shared components

- `CustomColors`: one palette; `AppColors` remains a semantic alias without duplicate color values.
- `CustomTextField`: input styling, focus, validation, formatters, multiline fields, optional fixed +91 and password visibility.
- `CustomDropdown`: expanded, styled dropdowns that fit narrow dialog layouts.
- `CustomButton`: filled, outline, text and icon variants; disabled/loading children and keyboard focus are preserved.
- `CustomDialog`: rounded, scrollable dialog shell, close affordance and wrapping actions.
- `CustomSurface`, `CustomStatusBadge`, `CustomStatCard`, `CustomQuickAction`, `CustomEmptyState` and `HotelRoomCard`.
- `ResponsivePage`/`ResponsiveUi`: adaptive readable form width, spacing and keyboard scrolling.

## Feature coverage

| Area | Updated presentation | Existing actions retained |
| --- | --- | --- |
| Signup/login | Shared cream/sage forms | +91 OTP, owner/hotel details, validation |
| OTP | Light verification screen and custom digit inputs | Auto advance, paste, keyboard navigation, resend timer, automatic/manual verification |
| Splash | Centralized brand palette and animation | Launch/session routing |
| Home | Compact status count tiles above all rooms on Home; bottom navigation to Edit rooms, More and Settings | Refresh/pull refresh, direct room creation, edit/delete, reports, guests, expenses, settings, backup, fresh-start protection, sign out |
| Booking and future booking | Shared fields, dropdowns, buttons and dialog shell | Guest/ID capture, OCR, additional guests, dates/times, rate, advances, GST, payment mode |
| Room controls | Shared dialog/actions | Extra days, charges, part payments, room change, checkout, cleaning and maintenance |
| Guests | Shared forms/dialogs and palette | Search, edit identity/photos, stay history, ID printing |
| Bills and booking details | New palette and dialog controls | Discounts, advances, payments, GST, receipt/slip printing |
| Reports | Shared surface, dates and actions | Date range, room/customer/payment summaries and PDF exports |
| Expenses | Responsive custom form/dropdowns/actions | Categories, amount/mode, delete and print/export |
| Edit rooms | Dedicated room list with direct Edit/Delete actions | Existing confirmed Firebase save/delete flow; active/upcoming bookings protected; Home refreshes from the same shared room list |
| Settings | Embedded shared HotelSettingsForm; drafts preserved across tabs | Hotel details, GST, admin password and save feedback only. More retains guests, reports, expenses, backup, protected fresh start, membership and sign-out. Legacy sheet entry reuses the same form. |
| License | New membership screen and custom keypad presentation | Trial status, PIN activation/renewal, continue trial |
| Backup/restore and confirmations | Shared dialog/buttons | Explicit downloads/imports and cloud-reset protections |

The production app's import boundary still excludes cPanel and device business-data storage. Historical PHP/UI compatibility files are retained outside that dependency graph.

## Validation

- Responsive dashboard tests: 320-pixel phone, tablet, desktop and landscape.
- Phone-width dialog checks: settings, booking, expenses, reports, guests, edit guest, room controls, booking details, bill preview and backup/restore.
- OTP/membership compact-screen checks.
- Full Flutter suite passed after the rebuild; Firebase/Auth/Storage/admin rules and server tests also passed.
- Preview: `docs/validation/modern-ui/dashboard.png` (isolated test fixture, not production hotel data).

Live Firebase access remains denied for the connected CLI account. Live data reset, backend deployment and SHA certificate registration have not occurred. The verified fingerprints are in `docs/firebase-signing.md`.


Management navigation validation: 113 Flutter tests passed, including direct room targeting, Home updates after edit/delete, protected bookings, Settings drafts at phone/landscape sizes and rejection of settings saves before Firebase is connected. Preview artifacts: `docs/validation/modern-ui/edit-rooms.png` and `settings.png`.


Responsive correction: four destinations are Home / Edit rooms / More / Settings. Available-room actions use natural button height instead of the clipped 36px close action. Shared surfaces apply radius/clipping only to the outer material, with padding inside. Edit/Delete controls stack for large text on narrow screens. Sheets switch to whole-content scrolling on short or keyboard-constrained windows; reports avoid fixed-height filter columns and horizontal bill-action overflow. Validation: 119 Flutter tests passed, including enlarged-text portrait/landscape and keyboard regression cases; Android debug APK built successfully.
