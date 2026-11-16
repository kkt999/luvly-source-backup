# Luvly — Bride mobile application UI

This is the first Flutter UI implementation based on the bride-facing Chapter 4 screenshots in `BACS3403_FinalDoc__Khoo Khai Ther_.pdf` (PDF pages 696–701; repeated earlier in the document).

It is **not yet the complete production application**. This combined project now also includes the staff/manager web portal. See README.md for the combined project instructions.

## Open and run

Open this `luvly_unified` folder in VS Code or Android Studio, then run:

```powershell
flutter pub get
flutter devices
flutter run -d <your-emulator-device-id>
```

The Android emulator displays the **bride mobile app UI**. Running `flutter run -d chrome` displays the **staff/manager website**, not the bride UI. Both launch from lib/main.dart.

For an Android phone with USB debugging enabled:

```powershell
flutter devices
flutter run -d <your-device-id>
```

On the welcome screen, choose **Explore UI demo**. You can also preview registration/login with a valid-format email and any password of at least eight characters. Do not enter your real password: authentication is not connected yet.

## Implemented UI and interactions

| Module | Screens and local interactions |
|---|---|
| Account, profile and membership | Welcome, registration validation, login validation, reset confirmation, home, notifications, profile editing, measurements, body-scan guide, Silver membership, points and reward redemption |
| Dress catalogue and try-on | Search, style/price filters, dress details, size/colour selection, shortlist, sample recommendations, preparation guide, image-based try-on preview, saved-look history |
| Service packages | Package catalogue, details, required services, optional extras, calculated totals, review and confirmation |
| Appointments and progress | Upcoming/cancelled appointments, type/date/time selection, local slot-conflict checks, booking review, confirmation, details, rescheduling, cancellation, sample progress timeline |
| Payments | Overview, remaining balance, amount validation, method selection, promotional-code state preview, review, simulated success/failure, demo receipt and transaction history |
| Customer support | FAQ, scripted assistant, support-ticket form, search/status filters, conversation replies, read-only closed tickets |

Bottom navigation stays consistent: **Home · Dresses · Bookings · Support · Profile**. Packages and Payments are accessible from Home; Payments are also accessible from Profile.

## Important demo boundaries

- All state is in memory and resets when the application restarts or the browser reloads.
- No Firebase authentication, Firestore, file storage or staff website connection exists yet.
- No email, notification, support message or Google Calendar event is actually sent.
- AR, camera capture, body measurement and recommendation scores are visual previews, not functioning AI/ML features.
- No real payments occur. No bank/card credentials are requested. Demo receipts are clearly marked invalid for real transactions.
- Promo-code validation displays example states; discounts are not applied to the sample invoice.
- Photo export, external sharing and receipt PDF download are deferred rather than presented as completed operations.
- Prices, dates, membership privileges, progress milestones, staff names and customer data are sample values.
- Reference photos were cropped from the supplied screenshots and are temporary, low-resolution assets. Replace them with your own/licensed high-resolution dress photographs before release.

## Files

- `lib/main.dart`: application entry point and mobile-width preview shell.
- `lib/src/design.dart`: colours, typography and shared components.
- `lib/src/model.dart`: demo state and models (replace with repositories/backend services later).
- `lib/src/account.dart`, `home.dart`, `dresses.dart`, `appointments.dart`, `commerce.dart`, `support.dart`: screens grouped by module.
- `test/app_test.dart`: layout and interaction tests.
- `test/preview_test.dart`: rendered mobile preview images.
- `assets/fonts`: Roboto and Cormorant Garamond, with their licence files.

## Verification commands

```powershell
flutter analyze
flutter test test/app_test.dart
flutter test test/preview_test.dart --update-goldens
flutter build web --no-web-resources-cdn
flutter build apk --debug
```

The project was created with Flutter 3.38.8 / Dart 3.10.7. Android and browser builds can be made on Windows. Building/signing for iPhone requires macOS and Xcode; iOS has not been tested here.

## Suggested next stage

First review the screen layout and wording against your intended workflow. Then connect one complete flow at a time: Firebase account/profile → dresses and package data → appointments and staff assignment → payments → support → AR/recommendations. Build staff and manager views in the separate website with role-based permissions, not as mobile bride screens.
