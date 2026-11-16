import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/main.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/portal_auth.dart';
import 'package:luvly_app/admin/portal_login.dart';
import 'package:luvly_app/src/auth_service.dart';
import '../fake_accounts.dart';
import 'fake_staff.dart';

const staffAccess = StaffAccess('Jane', PortalRole.staff);
const managerAccess = StaffAccess('Manager Jane', PortalRole.manager);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAccounts accounts;
  late FakeStaff staff;
  late PortalSession session;
  setUp(() {
    accounts = FakeAccounts();
    staff = FakeStaff();
    session = PortalSession(accounts, staff);
  });
  tearDown(() async {
    session.dispose();
    await staff.close();
    await accounts.events.close();
  });

  test('Only explicitly active, valid roles grant access', () {
    expect(
      StaffAccess.fromMap({
        'name': 'Jane',
        'role': 'manager',
        'active': true,
      })?.role,
      PortalRole.manager,
    );
    for (final data in <Map<String, dynamic>?>[
      null,
      {},
      {'name': 'Jane', 'role': 'bride', 'active': true},
      {'name': 'Jane', 'role': 'manager', 'active': false},
      {'name': 'Jane', 'role': 'manager', 'active': 'true'},
      {'name': '', 'role': 'staff', 'active': true},
      {'name': 12, 'role': 'staff', 'active': true},
    ]) {
      expect(StaffAccess.fromMap(data), isNull);
    }
  });

  test('Restored Firebase account needs a server-confirmed role', () async {
    accounts.user = const AccountIdentity('staff-1', 'staff@example.com');
    staff.initial['staff-1'] = const StaffAccessSnapshot(
      managerAccess,
      confirmed: false,
    );
    session.start();
    await flush();
    expect(session.phase, PortalPhase.checking);
    expect(session.access, isNull);
    staff.emit('staff-1', const StaffAccessSnapshot(staffAccess));
    await flush();
    expect(session.phase, PortalPhase.ready);
    expect(session.access?.role, PortalRole.staff);
    // Losing server confirmation immediately hides privileged screens.
    staff.emit(
      'staff-1',
      const StaffAccessSnapshot(staffAccess, confirmed: false),
    );
    await flush();
    expect(session.phase, PortalPhase.checking);
    expect(session.access, isNull);
  });

  test('Customer account cannot enter without a staff document', () async {
    staff.initial['bride-a'] = const StaffAccessSnapshot(null);
    session.start();
    await flush();
    await session.signIn(' bride@example.com ', 'test');
    await flush();
    expect(session.phase, PortalPhase.denied);
    expect(session.access, isNull);
    expect(accounts.registerCalls, 0);
    expect(accounts.lastEmail, 'bride@example.com');
  });

  test('Role changes and revocation apply to an open session', () async {
    accounts.user = const AccountIdentity('staff-1', 'staff@example.com');
    staff.initial['staff-1'] = const StaffAccessSnapshot(managerAccess);
    session.start();
    await flush();
    expect(session.access?.role, PortalRole.manager);
    staff.emit('staff-1', const StaffAccessSnapshot(staffAccess));
    await flush();
    expect(session.access?.role, PortalRole.staff);
    staff.emit('staff-1', const StaffAccessSnapshot(null));
    await flush();
    expect(session.phase, PortalPhase.denied);
    expect(session.access, isNull);
  });

  test(
    'Wrong password stays signed out and duplicate submits are ignored',
    () async {
      accounts.loginError = FirebaseAuthException(code: 'wrong-password');
      accounts.loginWait = Completer<void>();
      session.start();
      await flush();
      final first = session.signIn('staff@example.com', 'wrong');
      await session.signIn('staff@example.com', 'wrong');
      expect(accounts.loginCalls, 1);
      accounts.loginWait!.complete();
      await first;
      expect(session.phase, PortalPhase.signedOut);
      expect(session.error, contains('incorrect'));
      expect(session.busy, false);
    },
  );

  test(
    'Account switching discards old access and logout clears identity',
    () async {
      accounts.user = const AccountIdentity('staff-1', 'staff@example.com');
      staff.initial['staff-1'] = const StaffAccessSnapshot(managerAccess);
      staff.initial['bride-2'] = const StaffAccessSnapshot(null);
      session.start();
      await flush();
      accounts.emit(const AccountIdentity('bride-2', 'bride@example.com'));
      await flush();
      staff.emit('staff-1', const StaffAccessSnapshot(managerAccess));
      await flush();
      expect(session.phase, PortalPhase.denied);
      expect(session.identity?.uid, 'bride-2');
      await session.signOut();
      await flush();
      expect(session.phase, PortalPhase.signedOut);
      expect(session.identity, isNull);
      expect(session.access, isNull);
    },
  );

  test('Access stream error blocks workspace and retry recovers', () async {
    accounts.user = const AccountIdentity('staff-1', 'staff@example.com');
    staff.initial['staff-1'] = const StaffAccessSnapshot(managerAccess);
    session.start();
    await flush();
    staff.channels['staff-1']!.addError(StateError('offline'));
    await flush();
    expect(session.phase, PortalPhase.blocked);
    expect(session.access, isNull);
    session.retry();
    await flush();
    expect(session.phase, PortalPhase.ready);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('Real login layout at $width has no demo role selector', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PortalApp(session: session));
      await tester.pumpAndSettle();
      expect(find.byType(PortalLoginScreen), findsOneWidget);
      expect(find.text('Choose a demo role'), findsNothing);
      expect(find.text('Enter manager workspace'), findsNothing);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(accounts.loginCalls, 0);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Reset password uses email-only request and generic confirmation',
    (tester) async {
      await tester.pumpWidget(PortalApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'person@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(accounts.resetCalls, 1);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(accounts.loginCalls, 0);
    },
  );

  testWidgets(
    'Authorized login displays real name; revocation clears dialogs',
    (tester) async {
      staff.initial['bride-a'] = const StaffAccessSnapshot(managerAccess);
      await tester.pumpWidget(PortalApp(session: session));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'manager@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Existing-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffWorkspace), findsOneWidget);
      expect(find.text('Welcome back, Manager Jane'), findsOneWidget);
      expect(find.text('Amelia Tan'), findsNothing);
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('Welcome back, Manager Jane')),
          builder: (_) => const AlertDialog(content: Text('Protected dialog')),
        ),
      );
      await tester.pumpAndSettle();
      staff.emit('bride-a', const StaffAccessSnapshot(null));
      await tester.pumpAndSettle();
      expect(find.text('Protected dialog'), findsNothing);
      expect(find.byType(StaffWorkspace), findsNothing);
      expect(find.text('Staff access required'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(PortalLoginScreen), findsOneWidget);
    },
  );

  testWidgets('Unconfirmed access times out without granting permissions', (
    tester,
  ) async {
    accounts.user = const AccountIdentity('staff-1', 'staff@example.com');
    await tester.pumpWidget(PortalApp(session: session));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('Unable to verify access'), findsOneWidget);
    expect(find.byType(StaffWorkspace), findsNothing);
  });
}
