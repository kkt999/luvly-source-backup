import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'package:luvly_app/src/google_account.dart';
import 'fake_accounts.dart';

class GoogleFake extends FakeAccounts implements GoogleAccountGateway {
  int googleCalls = 0;
  @override
  bool googleLinked = false;
  @override
  Future<void> signInGoogle() async {
    googleCalls++;
    if (loginWait != null) await loginWait!.future;
    if (loginError != null) throw loginError!;
    emit(const AccountIdentity('existing-uid', 'bride@example.com'));
  }

  @override
  Future<void> linkGoogle() async {
    googleLinked = true;
  }
}

class AuthStub extends Fake implements FirebaseAuth {
  User? user;
  int signIns = 0;
  @override
  User? get currentUser => user;
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signIns++;
    return CredentialStub();
  }
}

class CredentialStub extends Fake implements UserCredential {}

class UserStub extends Fake implements User {
  UserStub(this.uid);
  @override
  final String uid;
  int links = 0;
  Object? error;
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    if (error != null) throw error!;
    links++;
    return CredentialStub();
  }

  @override
  Future<void> reload() async {}
}

void main() {
  testWidgets('Google login requires terms review before opening provider', (
    tester,
  ) async {
    final fake = GoogleFake();
    final session = AccountSession(fake);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      AccountScope(
        session: session,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(fake.googleCalls, 0);
    expect(find.text('About this notice'), findsOneWidget);
  });
  testWidgets('linked account UI disables repeated linking', (tester) async {
    final fake = GoogleFake()..googleLinked = true;
    final session = AccountSession(fake);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      AccountScope(
        session: session,
        child: const MaterialApp(home: GoogleAccountScreen()),
      ),
    );
    expect(find.text('Google is linked'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Link Google account'),
    );
    expect(button.onPressed, isNull);
  });
  test('Google reuses existing profile and UID without registering', () async {
    final fake = GoogleFake()
      ..saved = const BrideProfile(name: 'Bride', phone: '0123456789');
    final session = AccountSession(fake);
    addTearDown(session.dispose);
    await session.signInGoogle();
    expect(session.phase, AccountPhase.ready);
    expect(session.identity!.uid, 'existing-uid');
    expect(session.profile, same(fake.saved));
    expect(fake.registerCalls, 0);
  });
  test(
    'new Google user must complete profile, not bypass onboarding',
    () async {
      final session = AccountSession(GoogleFake());
      addTearDown(session.dispose);
      await session.signInGoogle();
      expect(session.phase, AccountPhase.completeProfile);
    },
  );
  test('Google cancellation keeps user signed out and clears busy', () async {
    final session = AccountSession(
      GoogleFake()
        ..loginError = FirebaseAuthException(code: 'google-cancelled'),
    );
    addTearDown(session.dispose);
    await session.signInGoogle();
    expect(session.phase, AccountPhase.signedOut);
    expect(session.busy, false);
    expect(session.error, contains('cancelled'));
  });
  test('Google double-tap launches only one request', () async {
    final fake = GoogleFake()..loginWait = Completer<void>();
    final session = AccountSession(fake);
    addTearDown(session.dispose);
    final pending = session.signInGoogle();
    await session.signInGoogle();
    expect(fake.googleCalls, 1);
    fake.loginWait!.complete();
    await pending;
  });
  test('link uses linkWithCredential, never signs into another UID', () async {
    final user = UserStub('original-uid');
    final auth = AuthStub()..user = user;
    await GoogleAccountAuth(
      auth,
      credentialLoader: () async =>
          GoogleAuthProvider.credential(idToken: 'test'),
    ).link();
    expect(user.links, 1);
    expect(auth.signIns, 0);
    expect(auth.currentUser!.uid, 'original-uid');
  });
  test('account change during Google chooser aborts linking', () async {
    final original = UserStub('original');
    final auth = AuthStub()..user = original;
    final api = GoogleAccountAuth(
      auth,
      credentialLoader: () async {
        auth.user = UserStub('other');
        return GoogleAuthProvider.credential(idToken: 'test');
      },
    );
    await expectLater(api.link(), throwsA(isA<FirebaseAuthException>()));
    expect(original.links, 0);
    expect(auth.signIns, 0);
  });
  test('link conflict never merges or switches accounts', () async {
    final user = UserStub('original')
      ..error = FirebaseAuthException(code: 'credential-already-in-use');
    final auth = AuthStub()..user = user;
    await expectLater(
      GoogleAccountAuth(
        auth,
        credentialLoader: () async =>
            GoogleAuthProvider.credential(idToken: 'test'),
      ).link(),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.currentUser!.uid, 'original');
    expect(auth.signIns, 0);
    expect(accountError(user.error!), contains('No accounts were merged'));
  });
  test('signed-in account cannot be silently replaced by sign-in', () async {
    final auth = AuthStub()..user = UserStub('original');
    await expectLater(
      GoogleAccountAuth(auth).signIn(),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.signIns, 0);
  });
}
