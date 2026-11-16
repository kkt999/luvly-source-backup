import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/main.dart' as app;
import 'package:luvly_app/admin/main.dart';
import 'package:luvly_app/admin/portal_login.dart';
import 'package:luvly_app/admin/portal_auth.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'fake_accounts.dart';
import 'admin/fake_staff.dart';

void main() {
  test('Default entry point follows the actual build target', () {
    expect(
      app.createPlatformApp(),
      kIsWeb ? isA<PortalApp>() : isA<app.LuvlyApp>(),
    );
  });
  testWidgets('Web target opens only the management entry UI', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(app.createPlatformApp(isWeb: true), isA<PortalApp>());
    final session = PortalSession(FakeAccounts(), FakeStaff());
    addTearDown(session.dispose);
    await tester.pumpWidget(PortalApp(session: session));
    await tester.pumpAndSettle();
    expect(find.byType(PortalLoginScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Native target opens only the bride entry UI', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(app.createPlatformApp(isWeb: false), isA<app.LuvlyApp>());
    final session = AccountSession(FakeAccounts());
    addTearDown(session.dispose);
    await tester.pumpWidget(app.LuvlyApp(session: session));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(PortalLoginScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
