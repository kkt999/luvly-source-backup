# Luvly — one Flutter project

**6 October update:** AR neckline/display stability and the Firebase appointment request flow are implemented. Read [SUPERVISOR_FLOW_CHECKLIST.md](SUPERVISOR_FLOW_CHECKLIST.md) for the demo sequence, rule-deployment gate and remaining modules. Payment processing remains disabled. The older prototype notes below describe the earlier baseline where they conflict with that checklist.

Open **luvly_unified** (the folder containing pubspec.yaml) in Android Studio. Both interfaces use the same lib/main.dart. You do not need two projects or two Android Studio windows.

| Selected device | What opens |
| --- | --- |
| Chrome / any web browser | Staff & manager management portal |
| Android emulator / Android phone | Bride/customer app |
| iOS simulator / iPhone | Not yet configured for Firebase; requires macOS and a separate iOS Firebase registration |

## Run in Android Studio

Run `flutter pub get` in this folder. Open lib/main.dart, choose **Chrome** or your running **Android emulator** in the device selector, and press Run. Stop the previous run before changing targets, or launch separate sessions if you want both at once.

Terminal alternatives:

```powershell
flutter run -d chrome
flutter devices
flutter run -d <your-emulator-device-id>
```

Replace the placeholder with the ID from flutter devices, such as emulator-5554. Start an emulator in Android Studio Device Manager if none is listed. Open the Flutter root folder, not only the android subfolder. If the ZIP extracts into a wrapper folder, open the inner luvly_unified folder containing pubspec.yaml.

## Structure

- lib/main.dart: automatic web/native selection using kIsWeb.
- lib/bride_app.dart and lib/src/: bride mobile UI.
- lib/admin/: staff/manager web UI.
- assets/: shared fonts and sample images.
- android/, ios/, web/: platform runners.
- test/: mobile, admin, routing and visual tests.

The Dart package name remains luvly_app for compatibility; the folder name is luvly_unified. Run the root lib/main.dart, not a file in lib/admin.

## Prototype limitations

See [CHAPTER4_UI_CHECKLIST.md](CHAPTER4_UI_CHECKLIST.md) for the Chapter 4 alignment, permission interpretation and remaining UI/integration gaps.

Bride signup, sign-in, password reset and personal contact profiles now use Firebase. See [FIREBASE_AUTH_CHECKLIST.md](FIREBASE_AUTH_CHECKLIST.md) for deployment status and acceptance tests. The welcome screen no longer has a demo bypass. Real accounts start with no sample bookings/payments/shortlist/tickets and zero points. Android AR photos are stored per account on this phone, with no cloud backup. Old installation-wide photos are retained on disk but are not assigned to a new account.

The web entry uses Firebase email/password login and checks an administrator-assigned `staff/{uid}` document. There is no public staff signup or role chooser. See [STAFF_AUTH_CHECKLIST.md](STAFF_AUTH_CHECKLIST.md). Verified accounts enter the original dashboard, sidebar and module layouts. The **dress catalogue is connected**: managers add/edit/publish dresses, staff have read-only inventory access, and brides browse the same published records. See [CATALOGUE_CHECKLIST.md](CATALOGUE_CHECKLIST.md) for the first end-to-end test, media limitations and deployed rules. Other business repositories are not connected: dashboard totals show “—” and those modules retain unavailable states/disabled writes. Real sign-out and role/revocation checks remain active. Seeded UI fixtures remain test-only through `PortalPreviewApp`; real accounts never receive those records. Bride bookings, packages, rewards and other unfinished business screens still have labelled prototype content/local-only actions. Favourites, dress-specific AR linking, real payments, calendar synchronization and messaging remain to be implemented. Platform selection is not a security boundary. Resizing the browser does not change the interface into the bride app.

Legacy preview photos are low-resolution reference assets. The live catalogue instead uses manager-supplied HTTPS image links; use licensed, stable images and preview them before publishing. Android uses debug signing, not production release signing. Existing separate projects remain untouched.

## Verify and build

For the Android AR workflow, verified checks and outstanding real-person acceptance tests, see [AR_SUBMISSION_CHECKLIST.md](AR_SUBMISSION_CHECKLIST.md). Select a supported dress in the catalogue, start live try-on, tap **Preview · 10s**, then **Retake** or **Save look**. View and compare saved images under **Profile → My try-on history**. This is an appearance-preview prototype, not a measurement or validated fit prediction.

```powershell
flutter analyze
flutter test
flutter build web --no-web-resources-cdn --no-wasm-dry-run
flutter build apk --debug
```

Web output: build/web. Android demo APK: build/app/outputs/flutter-apk/app-debug.apk.
