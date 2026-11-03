# Booking photo and sheet verification — 3 November 2026

- A temporary diagnostic guest uploaded front/back JPEGs using the actual Android Firebase SDK and HotelCloudSyncService booking checkpoint. Both images were downloaded from Storage and decoded successfully.
- A temporary diagnostic room was booked through the same confirmed-save checkpoint and read back from live Firestore with BOOKED status.
- The diagnostic guest, room, booking and two Storage objects were removed afterwards. A second check found no diagnostic guest or photo objects. Real hotel bookings were not changed by this test.
- Photo upload failures now have separate state from photo restore failures. A missing image belonging to an old guest must not reject a new booking whose uploads have completed.
- Form validation and save/picker failures show root-overlay feedback above the sheet; the inline error remains near the confirmation button. Optional OCR failure does not reject an already selected image.
- Shared sheets reserve the bottom system safe area and move above the keyboard. Widget checks cover a 48-pixel navigation area and a 240-pixel keyboard, with toast feedback above the modal route.
- Flutter analysis: no issues. Full Flutter suite: 130 passed. Debug APK built and installed with the existing Firebase login preserved.

Old guest photos that never reached Storage have no downloadable file. They must be selected again; metadata alone cannot recover their bytes.
