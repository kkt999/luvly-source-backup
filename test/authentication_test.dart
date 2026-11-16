import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/bride_app.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'package:luvly_app/src/account_terms.dart';
import 'package:luvly_app/src/password_policy.dart';
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/model.dart';
import 'fake_accounts.dart';

const profile = BrideProfile(name: 'Jane Lim', phone: '0123456789');

class _EmptyFirestore extends FirebaseFirestorePlatform {
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;

  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      _EmptyCollection(this, collectionPath);
}

class _EmptyCollection extends CollectionReferencePlatform {
  _EmptyCollection(super.firestore, super.path);

  @override
  Map<String, dynamic> get parameters => const {'where': <List<dynamic>>[]};

  @override
  QueryPlatform where(List<List<dynamic>> conditions) => this;

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    ServerTimestampBehavior serverTimestampBehavior =
        ServerTimestampBehavior.none,
    ListenSource listenSource = ListenSource.defaultSource,
  }) => Stream.value(
    QuerySnapshotPlatform([], [], SnapshotMetadataPlatform(false, false)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseFirestorePlatform.instance = _EmptyFirestore();
  });

  test('signup saves profile with no seeded identity or balances', () async {
    final backend = FakeAccounts();
    final session = AccountSession(backend);
    addTearDown(session.dispose);
    await session.register(
      'jane@example.com',
      'password123',
      'Jane Lim',
      '0123456789',
    );
    expect(session.phase, AccountPhase.ready);
    expect(backend.saved!.name, 'Jane Lim');
    expect(backend.saved!.points, 0);
    final model = AppModel.live();
    expect(model.name, '');
    expect(model.bookings, isEmpty);
    expect(model.payments, isEmpty);
    expect(model.shortlist, isEmpty);
    expect(model.tickets, isEmpty);
    expect(model.points, 0);
  });
  test('failed password never opens the account', () async {
    final backend = FakeAccounts()
      ..loginError = FirebaseAuthException(code: 'invalid-credential');
    final session = AccountSession(backend);
    addTearDown(session.dispose);
    await session.signIn('jane@example.com', 'wrong');
    expect(session.phase, AccountPhase.signedOut);
    expect(session.profile, isNull);
    expect(session.error, contains('incorrect'));
  });
  test('duplicate submits trigger only one sign-in request', () async {
    final backend = FakeAccounts()
      ..saved = profile
      ..loginWait = Completer<void>();
    final s = AccountSession(backend);
    addTearDown(s.dispose);
    final request = s.signIn('jane@example.com', 'secret');
    await s.signIn('jane@example.com', 'secret');
    expect(backend.loginCalls, 1);
    backend.loginWait!.complete();
    await request;
    expect(s.phase, AccountPhase.ready);
  });
  test(
    'interrupted signup recovers without creating a second auth account',
    () async {
      final b = FakeAccounts()
        ..saveError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
      final s = AccountSession(b);
      addTearDown(s.dispose);
      await s.register(
        'jane@example.com',
        'password123',
        'Jane Lim',
        '0123456789',
      );
      expect(s.phase, AccountPhase.blocked);
      expect(s.identity, isNotNull);
      b.saveError = null;
      await s.retry();
      expect(s.phase, AccountPhase.completeProfile);
      await s.completeProfile('Jane Lim', '0123456789');
      expect(s.phase, AccountPhase.ready);
      expect(b.registerCalls, 1);
    },
  );
  test(
    'profile failure blocks home, retry preserves existing profile',
    () async {
      final b = FakeAccounts()
        ..saved = profile
        ..profileError = TimeoutException('network');
      final s = AccountSession(b);
      addTearDown(s.dispose);
      await s.signIn('jane@example.com', 'password123');
      expect(s.phase, AccountPhase.blocked);
      b.profileError = null;
      await s.retry();
      expect(s.profile, same(profile));
      await s.signOut();
      expect(s.phase, AccountPhase.signedOut);
      expect(s.profile, isNull);
    },
  );
  test('validation and error messages do not expose service details', () {
    for (final weak in [
      '12345678',
      'abcdefgh',
      'ABCDEFGH',
      'Abcdef12',
      'abcdef1!',
      'ABCDEF1!',
      'Abcdefg!',
      'Ab1!',
      'Aa1!${'x' * 125}',
    ]) {
      expect(validateNewPassword(weak), isNotNull, reason: weak);
    }
    expect(validateNewPassword('Aunique1!pass'), isNull);
    expect(validateNewPassword('Aa1!${'x' * 124}'), isNull);
    for (final symbol in passwordSymbols.split('')) {
      expect(validateNewPassword('Abcdefg1$symbol'), isNull);
    }
    expect(validateEmail(' jane@example.com '), isNull);
    expect(validateEmail('bad@'), isNotNull);
    expect(validatePhone('123'), isNotNull);
    expect(validatePhone('+60 12-345 6789'), isNull);
    expect(
      accountError(FirebaseAuthException(code: 'user-not-found')),
      accountError(FirebaseAuthException(code: 'wrong-password')),
    );
  });
  Future<AccountSession> open(
    WidgetTester t,
    FakeAccounts b, {
    AppModel? model,
  }) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    final s = AccountSession(b);
    addTearDown(s.dispose);
    await t.pumpWidget(LuvlyApp(session: s, model: model));
    await t.pumpAndSettle();
    return s;
  }

  testWidgets('welcome has no demo bypass; sign-in rejects wrong credentials', (
    t,
  ) async {
    final b = FakeAccounts()
      ..loginError = FirebaseAuthException(code: 'invalid-credential');
    await open(t, b);
    expect(find.text('Explore UI demo'), findsNothing);
    await t.ensureVisible(find.text('I already have an account'));
    await t.tap(find.text('I already have an account'));
    await t.pumpAndSettle();
    expect(find.textContaining('Your password is handled'), findsNothing);
    await t.enterText(find.byType(TextFormField).at(0), 'jane@example.com');
    await t.enterText(find.byType(TextFormField).at(1), 'wrong');
    await t.ensureVisible(find.text('Sign in'));
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Email or password is incorrect'),
      findsOneWidget,
    );
    expect(find.byType(HomeShell), findsNothing);
  });
  testWidgets(
    'saved session restores identity; expiry clears nested routes and personal state',
    (t) async {
      final b = FakeAccounts()
        ..user = const AccountIdentity('bride-a', 'jane@example.com')
        ..saved = profile;
      final model = AppModel.live();
      await open(t, b, model: model);
      expect(find.textContaining('Hello, Jane'), findsOneWidget);
      expect(find.text('Hello, Sophia'), findsNothing);
      expect(model.points, 0);
      expect(model.bookings, isEmpty);
      final c = t.element(find.byType(HomeShell));
      Navigator.of(c).push(
        MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
      );
      await t.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      b.emit(null);
      await t.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(model.name, '');
      expect(model.accountId, isNull);
    },
  );
  testWidgets('reset sends request and uses a non-enumerating confirmation', (
    t,
  ) async {
    final b = FakeAccounts();
    await open(t, b);
    await t.ensureVisible(find.text('I already have an account'));
    await t.tap(find.text('I already have an account'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Forgot password?'));
    await t.tap(find.text('Forgot password?'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'jane@example.com');
    await t.tap(find.text('Send reset link'));
    await t.pumpAndSettle();
    expect(b.resetCalls, 1);
    expect(find.textContaining('If an account exists'), findsOneWidget);
  });
  testWidgets(
    'signup needs matching passwords and consent before Firebase request',
    (t) async {
      final b = FakeAccounts();
      await open(t, b);
      await t.ensureVisible(find.text('Get started'));
      await t.tap(find.text('Get started'));
      await t.pumpAndSettle();
      expect(find.textContaining('Open the terms, scroll'), findsNothing);
      expect(find.textContaining('Your password is handled'), findsNothing);
      expect(find.text('Read Terms & Conditions'), findsOneWidget);
      expect(find.text('An uppercase letter (A–Z)'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).at(0), 'Jane Lim');
      await t.enterText(find.byType(TextFormField).at(1), 'jane@example.com');
      await t.enterText(find.byType(TextFormField).at(2), '0123456789');
      await t.enterText(find.byType(TextFormField).at(3), 'Aunique1!pass');
      await t.enterText(find.byType(TextFormField).at(4), 'different');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Create account');
      await t.ensureVisible(submit);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      final readTerms = find.text('Read Terms & Conditions');
      await t.ensureVisible(readTerms);
      await t.tap(readTerms);
      await t.pumpAndSettle();
      final agree = find.widgetWithText(FilledButton, 'I agree');
      expect(t.widget<FilledButton>(agree).onPressed, isNull);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.ensureVisible(readTerms);
      await t.tap(readTerms);
      await t.pumpAndSettle();
      final scroll = t
          .widget<SingleChildScrollView>(find.byKey(const Key('terms-scroll')))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(agree).onPressed, isNotNull);
      await t.tap(agree);
      await t.pumpAndSettle();
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(b.registerCalls, 0);
      await t.enterText(find.byType(TextFormField).at(4), 'Aunique1!pass');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(submit);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      expect(b.registerCalls, 0);
      await t.ensureVisible(readTerms);
      await t.tap(readTerms);
      await t.pumpAndSettle();
      final scrollAgain = t
          .widget<SingleChildScrollView>(find.byKey(const Key('terms-scroll')))
          .controller!;
      scrollAgain.jumpTo(scrollAgain.position.maxScrollExtent);
      await t.pumpAndSettle();
      await t.tap(agree);
      await t.pumpAndSettle();
      await t.ensureVisible(submit);
      await t.pumpAndSettle();
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(b.registerCalls, 1);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.textContaining('Hello, Jane'), findsOneWidget);
    },
  );
  testWidgets(
    'terms closing does not accept; a large viewport can reach the end',
    (t) async {
      t.view.physicalSize = const Size(1200, 5000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const MaterialApp(home: AccountTermsScreen()));
      await t.pumpAndSettle();
      final scroll = t
          .widget<SingleChildScrollView>(find.byKey(const Key('terms-scroll')))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'I agree'))
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'profile save refreshes the displayed identity and keeps email read-only',
    (t) async {
      final b = FakeAccounts()
        ..user = const AccountIdentity('bride-a', 'jane@example.com')
        ..saved = profile;
      final model = AppModel.live();
      await open(t, b, model: model);
      Navigator.of(t.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
      );
      await t.pumpAndSettle();
      expect(find.text('Sign-in email'), findsOneWidget);
      expect(
        t.widget<SelectableText>(find.byType(SelectableText)).data,
        'jane@example.com',
      );
      expect(
        find.widgetWithText(TextFormField, 'jane@example.com'),
        findsNothing,
      );
      await t.enterText(find.byType(TextFormField).first, 'Alice Lim');
      await t.pump();
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();
      expect(b.saved!.name, 'Alice Lim');
      expect(model.name, 'Alice Lim');
      expect(find.textContaining('Hello, Alice'), findsOneWidget);
    },
  );
}
