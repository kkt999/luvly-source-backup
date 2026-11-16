import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/preview_app.dart';
import 'package:luvly_app/admin/model.dart';

void main() {
  test('Staff scope and restricted mutations', () {
    final m = PortalModel()..login(PortalRole.staff);
    expect(m.canOpen(PortalPage.reports), false);
    expect(m.canOpen(PortalPage.staff), false);
    expect(m.visibleTasks.every((t) => t.staffId == m.current!.id), true);
    expect(() => m.assignTask(m.tasks.first, 'S002'), throwsStateError);
    expect(
      () => m.saveGown(m.gowns.first, existing: m.gowns.first),
      returnsNormally,
    );
    expect(
      () => m.updateTask(
        m.tasks.firstWhere((t) => t.staffId != m.current!.id),
        'Completed',
        '',
      ),
      throwsStateError,
    );
    final own = m.visibleTasks.first;
    m.updateTask(own, 'Completed', 'Done');
    expect(own.status, 'Completed');
  });
  test(
    'Manager assignment affects staff scope; closed tickets are read-only',
    () {
      final m = PortalModel()..login(PortalRole.manager);
      final t = m.tasks.first;
      m.assignTask(t, 'S002');
      m.login(PortalRole.staff);
      expect(m.visibleTasks.contains(t), false);
      m.login(PortalRole.manager);
      final ticket = m.tickets.first;
      m.ticketStatus(ticket, 'Closed');
      expect(() => m.reply(ticket, 'Hello'), throwsStateError);
      expect(() => m.ticketStatus(ticket, 'In Progress'), throwsStateError);
    },
  );
  test('Manager cannot deactivate self; bookings reject conflicts', () {
    final m = PortalModel()..login(PortalRole.manager);
    final self = m.current!;
    expect(
      () => m.saveStaff(
        TeamMember(self.id, self.name, self.email, self.role, active: false),
        existing: self,
      ),
      throwsStateError,
    );
    final a = m.appointments.firstWhere(
      (a) => a.staffId != null && a.status == 'Confirmed',
    );
    expect(
      () => m.saveAppointment(
        Appointment('duplicate', a.brideId, a.type, a.date, a.hour, a.staffId),
      ),
      throwsStateError,
    );
  });

  for (final role in PortalRole.values) {
    testWidgets('${role.name} screens render and enforce navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = PortalModel(today: DateTime(2026, 9, 18))..login(role);
      await tester.pumpWidget(PortalPreviewApp(model: m));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final p in PortalPage.values.where(m.canOpen)) {
        final item = find.byKey(ValueKey('nav-${p.name}'));
        await tester.scrollUntilVisible(
          item,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: p.label);
      }
      if (role == PortalRole.staff) {
        expect(find.text('Reports'), findsNothing);
        expect(find.text('Staff accounts'), findsNothing);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('nav-inventory')),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-inventory')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'no-match-xyz');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Manager forms and compact layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final m = PortalModel()..login(PortalRole.manager);
    await tester.pumpWidget(PortalPreviewApp(model: m));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New appointment'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-rentals')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Customer support').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View ticket').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    m.logout();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    m.login(PortalRole.staff);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Visual review captures', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('LuvlySans');
      font.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/roboto-regular.ttf').readAsBytesSync(),
          ),
        ),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final m = PortalModel(today: DateTime(2026, 9, 18));
    const key = ValueKey('capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: PortalPreviewApp(model: m),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/login.png'));
    m.login(PortalRole.manager);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/manager.png'),
    );
    for (final p in [
      PortalPage.inventory,
      PortalPage.support,
      PortalPage.reports,
      PortalPage.schedule,
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('nav-${p.name}')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('nav-${p.name}')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/${p.name}.png'),
      );
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('nav-inventory')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inventory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View').first);
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/golden.jpg'),
        tester.element(find.byType(PortalPreviewApp)),
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/dress-details.png'),
    );
    await tester.tap(find.byKey(const ValueKey('nav-rentals')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/progress-details.png'),
    );
    m.logout();
    await tester.pumpAndSettle();
    m.login(PortalRole.staff);
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/staff.png'));
  });
}
