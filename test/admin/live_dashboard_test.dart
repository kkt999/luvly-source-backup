import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/workspace/notifications.dart';
import 'package:luvly_app/admin/main.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/overview.dart';
import 'package:luvly_app/admin/portal_auth.dart';
import 'package:luvly_app/admin/portal_login.dart';
import 'package:luvly_app/admin/shell.dart' show PortalShell;
import 'package:luvly_app/src/auth_service.dart';
import '../fake_accounts.dart';
import '../booking_flow_test.dart' show MemoryBookings;
import 'fake_staff.dart';
import '../fake_catalogue.dart';

void main() {
  test('Live model contains verified identity and no sample business data', () {
    final model = PortalModel.live(
      member: TeamMember('uid', 'CYJ', 'owner@example.com', PortalRole.manager),
    );
    addTearDown(model.dispose);
    expect(model.current!.name, 'CYJ');
    for (final records in [
      model.brides,
      model.team,
      model.gowns,
      model.packages,
      model.appointments,
      model.tasks,
      model.payments,
      model.tickets,
      model.availability,
      model.packageBookings,
      model.activity,
    ]) {
      expect(records, isEmpty);
    }
    expect(() => model.login(PortalRole.staff), throwsStateError);
    expect(
      () => model.saveGown(Gown('x', 'Fake', 'A-Line', 1, 'golden')),
      throwsStateError,
    );
    expect(
      () => model.saveStaff(
        TeamMember('x', 'Fake', 'fake@example.com', PortalRole.manager),
      ),
      throwsStateError,
    );
    expect(
      () => model.saveAppointment(
        Appointment('x', 'bride', 'Trial', model.today, 10, null),
      ),
      throwsStateError,
    );
    expect(
      () =>
          model.saveAvailability(Availability('uid', model.today, 9, 18, true)),
      throwsStateError,
    );
    expect(model.current!.role, PortalRole.manager);
  });

  testWidgets(
    'Specialist workspace hides counter navigation after work role changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = FakeAccounts()
        ..user = const AccountIdentity('uid', 'front@example.com');
      final staff = FakeStaff()
        ..initial['uid'] = const StaffAccessSnapshot(
          StaffAccess('Employee', PortalRole.staff, frontDesk: true),
        );
      final session = PortalSession(accounts, staff);
      addTearDown(() async {
        session.dispose();
        await accounts.events.close();
        await staff.close();
      });
      await tester.pumpWidget(
        PortalApp(session: session, bookings: MemoryBookings()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-payments')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-rentals')), findsOneWidget);
      staff.emit(
        'uid',
        const StaffAccessSnapshot(StaffAccess('Employee', PortalRole.staff)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-payments')), findsNothing);
      expect(find.byKey(const ValueKey('nav-rentals')), findsNothing);
      expect(find.text('My appointments'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('nav-appointments')));
      await tester.pumpAndSettle();
      expect(find.text('Payments & receipts'), findsNothing);
    },
  );

  for (final role in PortalRole.values) {
    testWidgets(
      'Verified ${role.name} has original navigation and safe empty pages',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final accounts = FakeAccounts()
          ..user = const AccountIdentity('uid', 'owner@example.com');
        final staff = FakeStaff()
          ..initial['uid'] = StaffAccessSnapshot(
            StaffAccess('CYJ', role, frontDesk: role == PortalRole.staff),
          );
        final session = PortalSession(accounts, staff);
        addTearDown(() async {
          session.dispose();
          await accounts.events.close();
          await staff.close();
        });
        final catalogue = FakeCatalogue();
        addTearDown(catalogue.changes.close);
        await tester.pumpWidget(
          PortalApp(
            session: session,
            catalogue: catalogue,
            bookings: MemoryBookings(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PortalShell), findsOneWidget);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.text('Welcome back, CYJ'), findsOneWidget);
        // No Firebase backend in this test: never fabricate a zero total.
        expect(find.text('Could not load dashboard data.'), findsOneWidget);
        expect(find.text('Manage appointments'), findsOneWidget);
        expect(find.text('Workspace setup in progress'), findsNothing);
        if (role == PortalRole.staff) {
          expect(find.text('Staff accounts'), findsNothing);
          expect(find.text('Reports'), findsNothing);
        }
        final model = PortalScope.of(
          tester.element(find.byType(DashboardPage)),
        );
        for (final page in model.pages) {
          final link = find.byKey(ValueKey('nav-${page.name}'));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(find.text('Luvly Portal   /   ${page.label}'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: page.label);
          expect(find.textContaining('Demo data only'), findsNothing);
          expect(find.textContaining('Sophia'), findsNothing);
          expect(find.text('Amelia Tan'), findsNothing);
          // All entry actions that would mutate unconnected data are disabled.
          for (final button in tester.widgetList<FilledButton>(
            find.byType(FilledButton),
          )) {
            if (page != PortalPage.inventory &&
                page != PortalPage.dashboard &&
                page != PortalPage.reports) {
              expect(button.onPressed, isNull, reason: page.label);
            }
          }
        }
        if (role == PortalRole.manager) {
          await tester.tap(find.text('Reports').first);
          await tester.pumpAndSettle();
          // Read-only date filters/retry are connected; missing credentials
          // show an error, never the former prototype's fake report totals.
          expect(find.text('Analytics Dashboard'), findsOneWidget);
          expect(find.text('Could not load dashboard data.'), findsOneWidget);
          expect(find.text('Generate Report'), findsNothing);
          expect(find.text('Export full CSV'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.scrollUntilVisible(
          find.text('Dashboard'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dashboard').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NotificationBell));
        await tester.pumpAndSettle();
        expect(find.byType(InboxScreen), findsOneWidget);
        expect(
          find.text(
            'You are all caught up. New notifications will appear here.',
          ),
          findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        // Actual Firebase session sign-out, not local demo-model logout.
        if (role == PortalRole.manager) {
          await tester.tap(find.byTooltip('Account menu'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Sign out').last);
        } else {
          await tester.tap(find.text('Sign out'));
        }
        await tester.pumpAndSettle();
        expect(accounts.current, isNull);
        expect(find.byType(PortalLoginScreen), findsOneWidget);
        expect(find.byType(PortalShell), findsNothing);
      },
    );
  }

  testWidgets(
    'Narrow dashboard drawer works and role changes discard privileged pages',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = FakeAccounts()
        ..user = const AccountIdentity('uid', 'owner@example.com');
      final staff = FakeStaff()
        ..initial['uid'] = const StaffAccessSnapshot(
          StaffAccess('CYJ', PortalRole.manager),
        );
      final session = PortalSession(accounts, staff);
      addTearDown(() async {
        session.dispose();
        await accounts.events.close();
        await staff.close();
      });
      await tester.pumpWidget(PortalApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back, CYJ'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('nav-reports')),
        120,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-reports')));
      await tester.pumpAndSettle();
      expect(find.text('Analytics Dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      staff.emit(
        'uid',
        const StaffAccessSnapshot(StaffAccess('CYJ', PortalRole.staff)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Analytics Dashboard'), findsNothing);
      expect(find.text('Welcome back, CYJ'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Staff accounts'), findsNothing);
      staff.emit('uid', const StaffAccessSnapshot(null));
      await tester.pumpAndSettle();
      expect(find.byType(PortalShell), findsNothing);
      expect(find.text('Staff access required'), findsOneWidget);
    },
  );
}
