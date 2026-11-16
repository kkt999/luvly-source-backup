import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/profile/profile_photo.dart';
import 'package:luvly_app/profile/my_rentals.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/customer_package_details.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/support/assistant_launcher.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'google_account_test.dart' show GoogleFake;
import 'packages/package_test.dart' show FakePackages;
import 'customer_package_cards_test.dart' show plan;

class ProfilePackages extends FakePackages {
  int reads = 0, catalogueReads = 0;
  bool failRead = false;
  @override
  Future<List<BridalPackage>> catalogue() async {
    catalogueReads++;
    return super.catalogue();
  }

  @override
  Future<List<PackageSelection>> selections() async {
    reads++;
    if (failRead) {
      throw const PaymentFailure('Package connection unavailable. Retry.');
    }
    return super.selections();
  }
}

class SignOutAccounts extends GoogleFake {
  int signOutCalls = 0;
  @override
  Future<void> signOut() async {
    signOutCalls++;
    await super.signOut();
  }
}

class _ProfileSaveAccounts extends GoogleFake {
  int saves = 0;
  Completer<void>? waiting;
  Completer<void>? loading;

  @override
  Future<BrideProfile?> loadProfile(String uid) async {
    await loading?.future;
    return super.loadProfile(uid);
  }

  @override
  Future<void> updateProfile(String uid, BrideProfile profile) async {
    saves++;
    await waiting?.future;
    return super.updateProfile(uid, profile);
  }
}

_ProfileSaveAccounts _editorAccounts({String email = 'sarah@example.com'}) =>
    _ProfileSaveAccounts()
      ..user = AccountIdentity('bride-a', email)
      ..saved = const BrideProfile(name: 'Sarah Lim', phone: '+60123456789');

FilledButton saveChanges(WidgetTester t) =>
    t.widget(find.widgetWithText(FilledButton, 'Save changes'));

Map<String, dynamic> gownRecord(String id, {bool linked = false}) => {
  'id': id,
  'state': 'Locked',
  if (linked) 'packageSelectionId': 'plan-a',
  'pickupDate': '2026-10-25',
  'eventDate': '2026-10-26',
  'returnDate': '2026-10-27',
  'availableAgain': '2026-10-31',
  'depositCents': 10000,
  'gowns': [
    {
      'dressId': id,
      'name': linked ? 'Package gown duplicate' : 'Gown-only ivory dress',
      'size': 'M',
    },
  ],
};

Future<void> mount(
  WidgetTester t, {
  Widget? child,
  double width = 390,
  double scale = 1,
  bool google = true,
  bool signedIn = true,
  bool longName = false,
  GoogleFake? accounts,
  bool settle = true,
}) async {
  viewport(t, Size(width, 1000));
  final model = AppModel()
    ..accountId = signedIn ? 'bride-a' : null
    ..name = longName
        ? 'Alexandra Very Long Customer Name for Layout Review'
        : 'Sarah Lim'
    ..email = longName
        ? 'alexandra.long.email.address@example.com'
        : 'sarah@example.com';
  addTearDown(model.dispose);
  final gateway = accounts ?? GoogleFake();
  final session = AccountSession(gateway)..start();
  addTearDown(() async {
    session.dispose();
    await gateway.events.close();
  });
  Widget app = MaterialApp(
    theme: luvlyTheme,
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: w!,
    ),
    home: RepaintBoundary(
      key: const ValueKey('profile-capture'),
      child:
          child ?? const PageFrame(title: 'My profile', child: ProfileScreen()),
    ),
  );
  if (google) app = AccountScope(session: session, child: app);
  await t.pumpWidget(AppScope(model: model, child: app));
  if (settle) await t.pumpAndSettle();
}

Future<void> tapRow(WidgetTester t, String label) async {
  final matches = find.text(label);
  if (matches.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      matches,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
  }
  final f = matches.first;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(fonts);
  testWidgets(
    'profile keeps ordered groups, a privacy entry and one rental destination',
    (t) async {
      await mount(t);
      for (final label in [
        'Your details',
        'Your bridal plans',
        'Account & connections',
        'Personal profile',
        'Body information',
        'Payments & receipts',
        'My shortlist',
        'Try-on history',
        'Google account',
        'Google Calendar',
        'Terms & privacy',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('My rentals & packages'), findsOneWidget);
      expect(find.text('My packages'), findsNothing);
      expect(find.text('My gown rentals'), findsNothing);
      expect(find.text('Offers & boutique news'), findsNothing);
      expect(find.byType(MenuTile), findsNothing);
      expect(
        t.getTopLeft(find.text('Your details')).dy,
        lessThan(t.getTopLeft(find.text('Your bridal plans')).dy),
      );
      expect(
        t.getTopLeft(find.text('Your bridal plans')).dy,
        lessThan(t.getTopLeft(find.text('Account & connections')).dy),
      );
      final avatar = t.widget<ProfilePhotoAvatar>(
        find.byType(ProfilePhotoAvatar),
      );
      expect(avatar.uid, 'bride-a');
      expect(avatar.editable, isTrue);
      await t.scrollUntilVisible(
        find.text('Sign out'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('email login can reset from profile using its sign-in address', (
    t,
  ) async {
    final accounts = GoogleFake()
      ..user = const AccountIdentity(
        'bride-a',
        'login@example.com',
        hasPassword: true,
      );
    await mount(t, accounts: accounts, width: 320, scale: 1.5);
    await tapRow(t, 'Reset password');
    expect(find.text('Change your Luvly password'), findsOneWidget);
    expect(find.text('login@example.com', findRichText: true), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tapRow(t, 'Send reset link');
    expect(accounts.resetCalls, 1);
    expect(accounts.lastEmail, 'login@example.com');
    expect(find.text('Check your inbox'), findsOneWidget);
    await tapRow(t, 'Back to profile');
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('Google-only account gets guidance in Google account', (t) async {
    final accounts = GoogleFake()
      ..googleLinked = true
      ..user = const AccountIdentity('bride-a', 'login@example.com');
    await mount(t, accounts: accounts);
    await tapRow(t, 'Google account');
    expect(
      find.textContaining('use your Google Account settings'),
      findsOneWidget,
    );
    expect(find.text('Send reset link'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Reset password'), findsNothing);
    expect(accounts.resetCalls, 0);
  });

  testWidgets('linked login can reset unless the active account changes', (
    t,
  ) async {
    final accounts = GoogleFake()
      ..googleLinked = true
      ..user = const AccountIdentity(
        'bride-a',
        'login@example.com',
        hasPassword: true,
      );
    await mount(t, accounts: accounts);
    await tapRow(t, 'Reset password');
    accounts.user = const AccountIdentity(
      'bride-b',
      'other@example.com',
      hasPassword: true,
    );
    await tapRow(t, 'Send reset link');
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    expect(accounts.resetCalls, 0);
  });

  testWidgets('profile privacy entry opens a read-only notice', (t) async {
    await mount(t);
    await tapRow(t, 'Terms & privacy');
    expect(find.widgetWithText(FilledButton, 'I agree'), findsNothing);
    expect(find.text('Your information, your choices.'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('contact and measurement editors remain reachable', (t) async {
    await mount(t);
    await tapRow(t, 'Personal profile');
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Change photo'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapRow(t, 'Body information');
    expect(find.byType(MeasurementsScreen), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('profile form edits contact details and keeps legacy fields', (
    t,
  ) async {
    final accounts = GoogleFake()
      ..user = const AccountIdentity('bride-a', 'sarah@example.com')
      ..saved = const BrideProfile(
        name: 'Sarah Lim',
        phone: '+60123456789',
        notes: 'Original note',
        contact: 'WhatsApp',
      );
    await mount(t, accounts: accounts, width: 320, scale: 2);
    await tapRow(t, 'Personal profile');
    expect(find.byType(AssistantExclusion), findsOneWidget);
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Preferred contact method'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await t.scrollUntilVisible(
      find.text('Sign-in email'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Used to sign in to Luvly.'), findsOneWidget);
    await t.ensureVisible(find.byType(TextFormField).first);
    await t.enterText(find.byType(TextFormField).first, 'Sarah Tan');
    await t.ensureVisible(find.byType(TextFormField).last);
    await t.enterText(find.byType(TextFormField).last, '012 345 6789');
    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();
    expect(accounts.saved!.name, 'Sarah Tan');
    expect(accounts.saved!.phone, '+60123456789');
    expect(accounts.saved!.notes, 'Original note');
    expect(accounts.saved!.contact, 'WhatsApp');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'initial account load and equivalent contact edits keep save disabled',
    (t) async {
      final accounts = _editorAccounts()..loading = Completer<void>();
      await mount(
        t,
        child: const EditProfileScreen(),
        accounts: accounts,
        settle: false,
      );
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(saveChanges(t).onPressed, isNull);
      accounts.loading!.complete();
      await t.pumpAndSettle();
      final name = find.byType(TextFormField).first;
      final phone = find.byType(TextFormField).last;
      expect(t.widget<TextFormField>(name).controller!.text, 'Sarah Lim');
      expect(t.widget<TextFormField>(phone).controller!.text, '123456789');
      for (final value in ['012 345 6789', '+60 (12) 345-6789', '123456789']) {
        await t.enterText(phone, value);
        await t.pumpAndSettle();
        expect(saveChanges(t).onPressed, isNull);
      }
      await t.enterText(name, '  Sarah   Lim ');
      await t.pumpAndSettle();
      expect(saveChanges(t).onPressed, isNull);
      await t.enterText(name, '李 静');
      await t.pumpAndSettle();
      expect(saveChanges(t).onPressed, isNotNull);
      await t.enterText(name, 'Sarah Lim');
      await t.pumpAndSettle();
      expect(saveChanges(t).onPressed, isNull);
      expect(accounts.saves, 0);
    },
  );

  testWidgets(
    'save validates inline, keeps failed drafts and blocks duplicate submissions',
    (t) async {
      final accounts = _editorAccounts();
      await mount(t, accounts: accounts);
      await tapRow(t, 'Personal profile');
      final name = find.byType(TextFormField).first;
      final phone = find.byType(TextFormField).last;
      await t.enterText(name, '123');
      await t.enterText(phone, '999');
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Use letters and normal name punctuation'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Enter a valid Malaysian phone number'),
        findsOneWidget,
      );
      expect(accounts.saves, 0);

      await t.enterText(name, '  李 静  ');
      await t.enterText(phone, ' 011 2345 6789 ');
      accounts.waiting = Completer<void>();
      accounts.saveError = StateError('private persistence detail');
      await t.tap(find.text('Save changes'));
      await t.pump();
      final busyButton = find.widgetWithText(FilledButton, 'Saving…');
      expect(t.widget<FilledButton>(busyButton).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(busyButton);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Discard changes?'), findsNothing);
      expect(accounts.saves, 1);
      expect(accounts.saved!.name, 'Sarah Lim');
      accounts.waiting!.complete();
      await t.pumpAndSettle();
      expect(
        find.text('Unable to complete the request. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private persistence detail'), findsNothing);
      expect(t.widget<TextFormField>(name).controller!.text.trim(), '李 静');
      expect(t.widget<TextFormField>(phone).controller!.text, '1123456789');
      expect(saveChanges(t).onPressed, isNotNull);
      accounts.saveError = null;
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();
      expect(accounts.saves, 2);
      expect(accounts.saved!.name, '李 静');
      expect(accounts.saved!.phone, '+601123456789');
      expect(find.text('Profile updated successfully.'), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsNothing);
    },
  );

  testWidgets(
    'AppBar and Android back protect contact edits and allow discarding them',
    (t) async {
      final accounts = _editorAccounts();
      await mount(t, accounts: accounts);
      await tapRow(t, 'Personal profile');
      expect(saveChanges(t).onPressed, isNull);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      await tapRow(t, 'Personal profile');
      final name = find.byType(TextFormField).first;
      await t.enterText(name, 'Sarah Tan');
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(t.widget<TextFormField>(name).controller!.text, 'Sarah Tan');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Discard changes'));
      await t.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(accounts.saves, 0);
    },
  );

  testWidgets('keyboard keeps save and phone usable at 320px and double text', (
    t,
  ) async {
    final email = '${'longprofileaddress' * 3}@example.com';
    final accounts = _editorAccounts(email: email);
    await mount(t, accounts: accounts, width: 320, scale: 2);
    t.view.physicalSize = const Size(320, 720);
    await t.pumpAndSettle();
    await tapRow(t, 'Personal profile');
    final fields = find.byType(TextFormField);
    await t.ensureVisible(fields.last);
    await t.tap(fields.last);
    t.view.viewInsets = const FakeViewPadding(bottom: 265);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    await t.ensureVisible(fields.last);
    await t.enterText(fields.last, '01123456789');
    await t.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save changes');
    expect(save.hitTestable(), findsOneWidget);
    expect(t.getBottomLeft(save).dy, lessThanOrEqualTo(455));
    expect(saveChanges(t).onPressed, isNotNull);
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(SelectableText));
    expect(t.widget<SelectableText>(find.byType(SelectableText)).data, email);
    expect(find.widgetWithText(TextFormField, email), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('empty sign-in email has a read-only fallback', (t) async {
    await mount(
      t,
      accounts: _editorAccounts(email: ''),
      child: const EditProfileScreen(),
    );
    expect(find.text('Email unavailable'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(saveChanges(t).onPressed, isNull);
  });
  testWidgets('Google sign-in stays a separate connection from Calendar', (
    t,
  ) async {
    await mount(t);
    await tapRow(t, 'Google account');
    expect(find.byType(GoogleAccountScreen), findsOneWidget);
    expect(
      find.textContaining('This does not connect Gmail or Google Calendar.'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('preview hides authenticated rental and connection entries', (
    t,
  ) async {
    await mount(t, google: false, signedIn: false);
    expect(find.text('My rentals & packages'), findsNothing);
    expect(find.text('Google Calendar'), findsNothing);
    expect(find.text('Account & connections'), findsNothing);
    expect(
      t.widget<ProfilePhotoAvatar>(find.byType(ProfilePhotoAvatar)).editable,
      isFalse,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('the single rental entry opens the unified workspace', (t) async {
    await mount(t);
    await tapRow(t, 'My rentals & packages');
    expect(find.byType(MyRentalsScreen), findsOneWidget);
    expect(find.text('Gown-only rentals'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('sign out still requires confirmation', (t) async {
    final accounts = SignOutAccounts();
    await mount(t, accounts: accounts);
    await tapRow(t, 'Sign out');
    expect(find.text('Sign out?'), findsOneWidget);
    expect(accounts.signOutCalls, 0);
    await tapRow(t, 'Keep current');
    expect(accounts.signOutCalls, 0);
    await tapRow(t, 'Sign out');
    await t.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await t.pumpAndSettle();
    expect(accounts.signOutCalls, 1);
    await t.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets(
      'grouped profile fits $width with double text and long identity',
      (t) async {
        await mount(t, width: width, scale: 2, longName: true);
        await t.scrollUntilVisible(
          find.text('Sign out'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('profile compact mobile visual', (t) async {
    await mount(t);
    await expectLater(
      find.byKey(const ValueKey('profile-capture')),
      matchesGoldenFile('previews/customer-profile-2078.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unified workspace keeps package details and separates gown-only records',
    (t) async {
      final packages = ProfilePackages()..rows.add(plan());
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add('${r.method} ${r.url.path}');
        return http.Response(
          jsonEncode({
            'serverNow': 1000,
            'limited': false,
            'rentals': [gownRecord('p', linked: true), gownRecord('solo')],
          }),
          200,
        );
      });
      final api = HttpPaymentApi(
        client: client,
        baseUrl: 'https://test.example',
        token: () async => 'synthetic-token',
      );
      addTearDown(api.close);
      await mount(
        t,
        child: MyRentalsScreen(packageApi: packages, rentalApi: api),
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(packages.catalogueReads, 0);
      expect(find.text('Bridal Essentials'), findsOneWidget);
      expect(find.text('My packages'), findsNothing);
      await tapRow(t, 'View package details');
      expect(find.byType(CustomerPackageDetails), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await tapRow(t, 'Gown-only rentals');
      expect(find.text('Gown-only ivory dress · Size M'), findsOneWidget);
      expect(find.text('Package gown duplicate · Size M'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      await t.tap(find.byTooltip('Refresh rentals'));
      await t.pumpAndSettle();
      expect(paths.length, greaterThanOrEqualTo(2));
      expect(paths.every((p) => p == 'GET /v1/rentals'), isTrue);
      await expectLater(
        find.byKey(const ValueKey('profile-capture')),
        matchesGoldenFile('previews/customer-gown-only-2077.png'),
      );
      await tapRow(t, 'Packages');
      expect(find.text('Bridal Essentials'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'package failures do not prevent access to separate gown records',
    (t) async {
      final packages = ProfilePackages()..failRead = true;
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode({'serverNow': 1000, 'limited': false, 'rentals': []}),
          200,
        ),
      );
      final api = HttpPaymentApi(
        client: client,
        baseUrl: 'https://test.example',
        token: () async => 'synthetic-token',
      );
      addTearDown(api.close);
      await mount(
        t,
        child: MyRentalsScreen(packageApi: packages, rentalApi: api),
      );
      expect(
        find.text('Package connection unavailable. Retry.'),
        findsOneWidget,
      );
      await tapRow(t, 'Gown-only rentals');
      expect(
        find.textContaining('No gown-only rental records yet.'),
        findsOneWidget,
      );
      await tapRow(t, 'Packages');
      packages.failRead = false;
      await tapRow(t, 'Retry');
      expect(find.text('Package connection unavailable. Retry.'), findsNothing);
      await tapRow(t, 'Browse packages');
      expect(packages.catalogueReads, 1);
      expect(find.text('Service packages'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('gown-only failure retries without inventing an empty result', (
    t,
  ) async {
    var fail = true;
    final client = MockClient(
      (r) async => fail
          ? http.Response('{}', 503)
          : http.Response(
              jsonEncode({'serverNow': 1000, 'limited': false, 'rentals': []}),
              200,
            ),
    );
    final api = HttpPaymentApi(
      client: client,
      baseUrl: 'https://test.example',
      token: () async => 'synthetic-token',
    );
    addTearDown(api.close);
    await mount(
      t,
      child: MyRentalsScreen(packageApi: ProfilePackages(), rentalApi: api),
    );
    await tapRow(t, 'Gown-only rentals');
    expect(
      find.textContaining('No gown-only rental records yet.'),
      findsNothing,
    );
    fail = false;
    await t.tap(find.byTooltip('Refresh rentals'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('No gown-only rental records yet.'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('unified rental tabs fit $width at double text scale', (
      t,
    ) async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode({'serverNow': 1000, 'limited': false, 'rentals': []}),
          200,
        ),
      );
      final api = HttpPaymentApi(
        client: client,
        baseUrl: 'https://test.example',
        token: () async => 'synthetic-token',
      );
      addTearDown(api.close);
      await mount(
        t,
        width: width,
        scale: 2,
        child: MyRentalsScreen(packageApi: ProfilePackages(), rentalApi: api),
      );
      expect(t.takeException(), isNull);
      await tapRow(t, 'Gown-only rentals');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
