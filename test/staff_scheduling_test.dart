import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/bookings/staff_scheduling_screen.dart';
import 'availability_calendar_test.dart'
    show CalendarFixture, tapVisible, renderCalendar;
import 'checkout_redesign_test.dart' show fonts, viewport;

Future<void> mount(
  WidgetTester t,
  CalendarFixture f, {
  double width = 1440,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1100));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: portalTheme,
      debugShowCheckedModeBanner: false,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: StaffSchedulingScreen(api: f.api, day: DateTime(2026, 10, 22)),
    ),
  );
  await t.pumpAndSettle();
}

Map<String, dynamic> pending() => {
  'id': 'a' * 32,
  'uid': 'mary',
  'staffName': 'Mary',
  'day': '2026-10-22',
  'startHour': 14,
  'endHour': 16,
  'reason': 'Personal appointment',
  'state': 'Pending',
  'revision': 1,
};
void main() {
  testWidgets(
    'staff see only own requests and no manager configuration or approvals',
    (t) async {
      final f = CalendarFixture()..requests.add({...pending(), 'uid': 'john'});
      addTearDown(f.api.close);
      await mount(t, f);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Team responsibilities'), findsNothing);
      expect(find.text('Minimum staffing'), findsNothing);
      await tapVisible(t, find.text('Withdraw'));
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts.single, {'action': 'Withdraw', 'revision': 1, 'note': ''});
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('manager approval is explicit and uses exact request revision', (
    t,
  ) async {
    final f = CalendarFixture()..manager = true;
    f.requests.add(pending());
    addTearDown(f.api.close);
    await mount(t, f);
    expect(f.posts, isEmpty);
    await tapVisible(t, find.text('Approve'));
    expect(f.posts, isEmpty);
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(f.posts.single, {'action': 'Approve', 'revision': 1, 'note': ''});
    expect(find.text('Mary · Approved'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'front desk profile is explicitly selected without mutating auth role',
    (t) async {
      final f = CalendarFixture()..manager = true;
      addTearDown(f.api.close);
      await mount(t, f);
      await tapVisible(t, find.byTooltip('Configure responsibilities').first);
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts, isEmpty);
      expect(find.text('Choose this employee’s work role.'), findsOneWidget);
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Front desk').last);
      await t.pumpAndSettle();
      await tapVisible(t, find.text('Confirm'));
      expect(f.posts.single, {
        'uid': 'john',
        'jobRole': 'FrontDesk',
        'serviceTypes': [],
        'revision': 0,
      });
      expect(f.posts.single.containsKey('role'), isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'minimum staffing sends explicit role/service minima with revision',
    (t) async {
      final f = CalendarFixture()..manager = true;
      addTearDown(f.api.close);
      await mount(t, f);
      await tapVisible(t, find.text('Minimum staffing'));
      await tapVisible(t, find.text('Confirm'));
      expect(f.posts.single['minimumOnDuty'], 1);
      expect(f.posts.single['revision'], 1);
      expect(f.posts.single['minimumByRole'], {
        'FrontDesk': 0,
        'Consultant': 0,
        'FittingSpecialist': 0,
        'MakeupArtist': 0,
      });
      expect(f.posts.single['requireServiceAssignments'], false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'front desk calendar can switch all and own without staffId override',
    (t) async {
      final f = CalendarFixture()..canViewAll = true;
      addTearDown(f.api.close);
      await renderCalendar(t, f);
      expect(find.text('All appointments'), findsOneWidget);
      await tapVisible(t, find.text('My assignments'));
      expect(
        f.gets.lastWhere((s) => s.contains('appointment-schedule')),
        contains('scope=own'),
      );
      expect(f.gets.any((s) => s.contains('staffId=')), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('specialist calendar does not offer global scope', (t) async {
    final f = CalendarFixture();
    addTearDown(f.api.close);
    await renderCalendar(t, f);
    expect(find.text('All appointments'), findsNothing);
    expect(f.posts, isEmpty);
  });
  for (final width in [320.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('staff scheduling fits $width at scale $scale', (t) async {
        final f = CalendarFixture()..manager = true;
        f.requests.add(pending());
        addTearDown(f.api.close);
        await mount(t, f, width: width, scale: scale);
        await tapVisible(t, find.text('Minimum staffing'));
        expect(t.takeException(), isNull);
        await tapVisible(t, find.text('Cancel'));
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('staff scheduling desktop visual', (t) async {
    final f = CalendarFixture()..manager = true;
    f.requests.add(pending());
    addTearDown(f.api.close);
    await mount(t, f);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/staff-scheduling-2070.png'),
    );
    expect(jsonEncode(f.context()), isNot(contains('password')));
    expect(t.takeException(), isNull);
  });
}
