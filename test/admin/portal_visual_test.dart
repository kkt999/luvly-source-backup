import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/main.dart';
import 'package:luvly_app/admin/design.dart';
import 'package:luvly_app/admin/shell.dart' show PortalShell;
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/portal_auth.dart';
import '../fake_accounts.dart';
import 'fake_staff.dart';
import 'analytics_test.dart' show FakeAnalytics;
import 'package:luvly_app/admin/analytics_api.dart' show AnalyticsScope;

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('Staff authentication visual review at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final entry in {
          'LuvlySans': 'assets/fonts/roboto-regular.ttf',
          'LuvlySerif': 'assets/fonts/CormorantGaramond.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final font = FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value));
          await font.load();
        }
      });
      final accounts = FakeAccounts();
      final staff = FakeStaff();
      final session = PortalSession(accounts, staff);
      addTearDown(() async {
        session.dispose();
        await accounts.events.close();
        await staff.close();
      });
      const capture = ValueKey('staff-auth-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: PortalApp(session: session, analytics: FakeAnalytics()),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile('goldens/staff-login-${width.toInt()}.png'),
      );
      staff.initial['bride-a'] = const StaffAccessSnapshot(
        StaffAccess('Jane Lim', PortalRole.manager),
      );
      await session.signIn('jane@example.com', 'synthetic-test-password');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PortalShell), findsOneWidget);
      // Same production shell, fixed date for repeatable visual baselines.
      // Authentication + all navigation are exercised in live_dashboard_test.
      final model = PortalModel.live(
        member: TeamMember(
          'bride-a',
          'Jane Lim',
          'jane@example.com',
          PortalRole.manager,
        ),
        today: DateTime(2026, 10, 2),
      );
      addTearDown(model.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AnalyticsScope(
            today: DateTime(2026, 10, 18),
            api: FakeAnalytics(),
            child: PortalScope(
              model: model,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: portalTheme,
                home: PortalShell(onSignOut: session.signOut),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile(
          width == 1440
              ? 'goldens/manager-welcome-1440-2078.png'
              : 'goldens/staff-welcome-${width.toInt()}.png',
        ),
      );
    });
  }
}
