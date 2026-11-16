import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/analytics_api.dart';
import 'package:luvly_app/admin/design.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/shell.dart' show PortalShell;
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import '../checkout_redesign_test.dart' show fonts, viewport;
import 'analytics_test.dart' show FakeAnalytics;

Future<PortalModel> shell(
  WidgetTester tester, {
  bool manager = true,
  double width = 1440,
  double scale = 1,
  String name = 'Jane Lim',
  VoidCallback? onSignOut,
}) async {
  viewport(tester, Size(width, 1100));
  final model = PortalModel.live(
    member: TeamMember(
      'uid',
      name,
      'jane@example.com',
      manager ? PortalRole.manager : PortalRole.staff,
      frontDesk: !manager,
    ),
    today: DateTime(2026, 10, 18),
  );
  addTearDown(model.dispose);
  await tester.pumpWidget(
    PortalScope(
      model: model,
      child: AnalyticsScope(
        today: DateTime(2026, 10, 18),
        api: FakeAnalytics(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: portalTheme,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: PortalShell(onSignOut: onSignOut ?? () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

void main() {
  test(
    'document palette is portal-only, with white navigation and wine primary actions',
    () {
      expect(portalTheme.colorScheme.primary, const Color(0xFFA20F3A));
      expect(portalTheme.appBarTheme.backgroundColor, Colors.white);
      expect(portalTheme.drawerTheme.backgroundColor, Colors.white);
      expect(portalTheme.scaffoldBackgroundColor, const Color(0xFFFCF9FA));
      expect(
        luvlyTheme.colorScheme.primary,
        isNot(portalTheme.colorScheme.primary),
      );
      final contrast =
          (Colors.white.computeLuminance() + .05) /
          (rose.computeLuminance() + .05);
      expect(contrast, greaterThan(4.5));
    },
  );
  for (final width in [320.0, 390.0, 1100.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'live shell fits $width at text $scale with a long account name',
        (tester) async {
          await shell(
            tester,
            width: width,
            scale: scale,
            name: 'Alexandra Very Long Account Name for Layout Review',
          );
          if (width < 1050) {
            await tester.tap(find.byTooltip('Open navigation'));
            await tester.pumpAndSettle();
          }
          final navigation = find.byKey(const ValueKey('nav-reports'));
          await tester.scrollUntilVisible(
            navigation,
            150,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('portal-navigation-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(navigation, findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'staff still has no management account or reporting access and sign-out callback remains intact',
    (tester) async {
      var signedOut = 0;
      final model = await shell(
        tester,
        manager: false,
        onSignOut: () => signedOut++,
      );
      expect(find.byKey(const ValueKey('nav-staff')), findsNothing);
      expect(find.byKey(const ValueKey('nav-reports')), findsNothing);
      expect(find.byKey(const ValueKey('nav-rentals')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-workflow')), findsNothing);
      expect(model.canOpen(PortalPage.staff), isFalse);
      expect(model.canOpen(PortalPage.reports), isFalse);
      expect(model.canOpen(PortalPage.reviews), isTrue);
      expect(find.byKey(const ValueKey('nav-reviews')), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      expect(signedOut, 1);
    },
  );
  testWidgets('empty account name does not crash avatar rendering', (
    tester,
  ) async {
    await shell(tester, name: '');
    expect(find.text('?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'record table gives large text enough height and keeps horizontal scrolling',
    (tester) async {
      viewport(tester, const Size(320, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: portalTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: PageBody(
                children: [
                  RecordTable(
                    connected: true,
                    columns: const ['Customer', 'Contact'],
                    minWidth: 760,
                    rows: [
                      [
                        cell('Jane Lim', sub: 'Bridal Essentials'),
                        cell('jane@example.com', sub: '0123456789'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Jane Lim'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final manager in [true, false]) {
    testWidgets(
      'document-aligned ${manager ? 'manager' : 'staff'} shell visual',
      (tester) async {
        await tester.runAsync(fonts);
        await shell(tester, manager: manager);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            manager
                ? 'goldens/document-manager-shell-2078.png'
                : 'goldens/document-staff-shell-2080.png',
          ),
        );
      },
    );
  }
}
