import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/bookings/availability_screen.dart';
import 'package:luvly_app/bookings/schedule_calendar.dart';
import 'package:luvly_app/bookings/booking_api.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

class CalendarFixture {
  bool manager = false, canViewAll = false;
  String scope = 'own';
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic> context() => {
    'uid': 'john',
    'manager': manager,
    'canViewAll': canViewAll,
    'policy': {
      'revision': 1,
      'minimumOnDuty': 1,
      'minimumByRole': {},
      'minimumByService': {},
      'requireServiceAssignments': false,
    },
    'profile': null,
    'requests': requests,
    'staff': manager
        ? [
            {'uid': 'john', 'name': 'John', 'profile': null},
            {
              'uid': 'mary',
              'name': 'Mary',
              'profile': {
                'jobRole': 'FittingSpecialist',
                'serviceTypes': ['Dress Trial'],
                'revision': 1,
              },
            },
          ]
        : [],
    'exceptions': [],
  };
  final own = <String, Map<String, dynamic>>{
    '2026-10-21': {'available': false, 'startHour': 14, 'endHour': 16},
  };
  final posts = <Map<String, dynamic>>[], gets = <String>[];
  int revision = 3;
  bool failMonth = false, failSave = false, badDay = false;
  Completer<http.Response>? delayedDay;
  List<Map<String, dynamic>> visits(String day) => day == '2026-10-20'
      ? [
          {
            'id': 'visit',
            'name': 'Jane Lim',
            'type': 'Dress Trial',
            'status': 'Confirmed',
            'startAt': DateTime.utc(2026, 10, 20, 2).millisecondsSinceEpoch,
          },
        ]
      : [];
  Map<String, dynamic> month(String month) {
    final first = DateTime.parse('$month-01'),
        count = DateTime(first.year, first.month + 1, 0).day;
    return {
      'month': month,
      'today': '2026-10-18',
      'editableUntil': '2027-04-15',
      'limited': false,
      'scope': scope,
      'canViewAll': canViewAll,
      'days': [
        for (var d = 1; d <= count; d++)
          {
            'day': bookingDay(DateTime(first.year, first.month, d)),
            'own': own[bookingDay(DateTime(first.year, first.month, d))],
            'appointments': visits(
              bookingDay(DateTime(first.year, first.month, d)),
            ),
          },
      ],
    };
  }

  http.Response day(String day) => http.Response(
    jsonEncode({
      'day': day,
      'own': own[day],
      'revision': revision,
      'assignedHours': day == '2026-10-20' ? [10] : [],
      'hours': badDay ? ['invalid'] : [11, 12, 14, 15, 16],
    }),
    200,
  );
  late final api = HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'token',
    client: MockClient((r) async {
      expect(r.headers['authorization'], 'Bearer token');
      if (r.method == 'POST') {
        final body = Map<String, dynamic>.from(jsonDecode(r.body));
        posts.add(body);
        if (failSave) {
          return http.Response(
            jsonEncode({'error': 'AVAILABILITY_CHANGED'}),
            409,
          );
        }
        if (r.url.path == '/v1/staff-time-off') {
          requests.add({
            'id': 'a' * 32,
            'uid': 'john',
            'staffName': 'John',
            'state': 'Pending',
            'revision': 1,
            ...body,
          });
        } else if (r.url.path.endsWith('/review')) {
          requests.first['state'] = body['action'] == 'Approve'
              ? 'Approved'
              : 'Rejected';
        }
        return http.Response('{}', 200);
      }
      gets.add(r.url.toString());
      if (r.url.path == '/v1/staff-scheduling') {
        return http.Response(jsonEncode(context()), 200);
      }
      if (r.url.path == '/v1/appointment-schedule') {
        scope = r.url.queryParameters['scope'] ?? (canViewAll ? 'all' : 'own');
        if (failMonth) {
          return http.Response('{"error":"SCHEDULE_LIMIT"}', 409);
        }
        return http.Response(
          jsonEncode(month(r.url.queryParameters['month']!)),
          200,
        );
      }
      expect(r.url.path, '/v1/appointment-availability');
      final requested = r.url.queryParameters['day']!;
      if (requested == '2026-10-20' && delayedDay != null) {
        return delayedDay!.future;
      }
      return day(requested);
    }),
  );
}

Future<void> renderCalendar(
  WidgetTester tester,
  CalendarFixture f, {
  double width = 1440,
  double scale = 1,
  VoidCallback? onAppointments,
}) async {
  viewport(tester, Size(width, 1200));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: portalTheme,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: LiveAvailabilityScreen(
          transport: f.api,
          manager: f.manager,
          onAppointments: onAppointments,
          now: () => DateTime(2026, 10, 18, 12),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> selectDay(WidgetTester tester, String day) =>
    tapVisible(tester, find.byKey(ValueKey('schedule-day-$day')));

void main() {
  test(
    'parser requires complete month and validates default vs absence and MYT visits',
    () {
      final f = CalendarFixture(),
          m = ScheduleMonth.fromJson(f.month('2026-10'), '2026-10');
      expect(m.days.length, 31);
      expect(m.days['2026-10-18']!.own, isNull);
      expect(m.days['2026-10-21']!.unavailable, isTrue);
      expect(m.days['2026-10-20']!.visits.single.time, '10:00–11:00');
      expect(m.editable(DateTime(2026, 10, 17)), isFalse);
      expect(m.editable(DateTime(2027, 4, 15)), isTrue);
      expect(m.editable(DateTime(2027, 4, 16)), isFalse);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['limited'] = true,
        (d) => (d['days'] as List).removeLast(),
        (d) => d['month'] = '2026-11',
        (d) => (d['days'] as List).last['own'] = {
          'available': false,
          'startHour': 17,
          'endHour': 10,
        },
      ]) {
        final data = f.month('2026-10');
        mutate(data);
        expect(
          () => ScheduleMonth.fromJson(data, '2026-10'),
          throwsA(isA<PaymentFailure>()),
        );
      }
    },
  );
  testWidgets(
    'calendar date positions, selection and visit details work without writes',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      var opened = 0;
      await renderCalendar(tester, f, onAppointments: () => opened++);
      expect(find.byType(ScheduleCalendar), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('schedule-day-2026-10-01')))
            .dx,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('schedule-day-2026-10-05')))
              .dx,
        ),
      );
      await selectDay(tester, '2026-10-20');
      expect(find.text('20 October 2026'), findsOneWidget);
      await tapVisible(tester, find.text('Jane Lim'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      await tester.tap(find.text('Open Appointments'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(f.posts, isEmpty);
    },
  );
  testWidgets(
    'time-off request uses selected date and never directly changes availability',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      await renderCalendar(tester, f);
      await selectDay(tester, '2026-10-22');
      await tapVisible(tester, find.text('Request time off'));
      await tester.enterText(
        find.byType(TextFormField).last,
        'Personal appointment',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(f.posts.single['day'], '2026-10-22');
      expect(f.posts.single['startHour'], 10);
      expect(f.posts.single['endHour'], 17);
      expect(f.posts.single.containsKey('staffId'), isFalse);
      expect(f.posts.single.containsKey('available'), isFalse);
      expect(f.own['2026-10-22'], isNull);
      expect(find.textContaining('Pending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel sends no request; failed request preserves draft and retry identity',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      await renderCalendar(tester, f);
      await tapVisible(tester, find.text('Request time off'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.posts, isEmpty);
      f.failSave = true;
      await tapVisible(tester, find.text('Request time off'));
      await tester.enterText(
        find.byType(TextFormField).last,
        'Personal appointment',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('This schedule changed. Refresh it before saving.'),
        findsOneWidget,
      );
      expect(find.text('Availability saved.'), findsNothing);
      expect(find.text('Personal appointment'), findsOneWidget);
      f.failSave = false;
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(f.posts.length, 2);
      expect(f.posts[0]['requestId'], f.posts[1]['requestId']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'month failure is an error, never an empty available calendar; retry recovers',
    (tester) async {
      final f = CalendarFixture()..failMonth = true;
      addTearDown(f.api.close);
      await renderCalendar(tester, f);
      expect(find.byType(ScheduleCalendar), findsNothing);
      expect(find.text('No assigned appointments on this date.'), findsNothing);
      f.failMonth = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleCalendar), findsOneWidget);
    },
  );
  testWidgets('old day response cannot overwrite the newly selected date', (
    tester,
  ) async {
    final f = CalendarFixture()..delayedDay = Completer<http.Response>();
    addTearDown(f.api.close);
    await renderCalendar(tester, f);
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-10-20')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-10-21')));
    await tester.pumpAndSettle();
    f.delayedDay!.complete(f.day('2026-10-20'));
    await tester.pumpAndSettle();
    expect(find.text('21 October 2026'), findsOneWidget);
    expect(find.text('Unavailable window'), findsOneWidget);
    expect(find.text('Jane Lim'), findsNothing);
  });
  testWidgets(
    'past date is read-only; today and month navigation keep dates aligned',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      await renderCalendar(tester, f);
      await selectDay(tester, '2026-10-17');
      expect(find.text('Request time off'), findsNothing);
      expect(f.gets.any((s) => s.contains('day=2026-10-17')), isFalse);
      await tapVisible(tester, find.text('Today'));
      expect(find.text('18 October 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('1 November 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
    },
  );
  testWidgets(
    'calendar search and marker filter combine; reset restores markers',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      await renderCalendar(tester, f);
      await tester.enterText(find.byType(TextField), 'Jane TRIAL');
      await tester.pumpAndSettle();
      expect(find.text('10:00 Jane Lim'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('Calendar entries-All entries')),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('list-option-Calendar entries-Unavailable')),
      );
      expect(find.text('10:00 Jane Lim'), findsNothing);
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('10:00 Jane Lim'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(f.posts, isEmpty);
    },
  );
  testWidgets('malformed daily data disables editing instead of crashing', (
    tester,
  ) async {
    final f = CalendarFixture()..badDay = true;
    addTearDown(f.api.close);
    await renderCalendar(tester, f);
    expect(
      find.text('Could not verify this day. Refresh before editing.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Request time off'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('calendar fits $width at text $scale', (tester) async {
        final f = CalendarFixture();
        addTearDown(f.api.close);
        await renderCalendar(tester, f, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await selectDay(tester, '2026-10-20');
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('calendar desktop visual with synthetic appointments', (
    tester,
  ) async {
    final f = CalendarFixture();
    addTearDown(f.api.close);
    await tester.runAsync(fonts);
    await renderCalendar(tester, f);
    await selectDay(tester, '2026-10-20');
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/availability-calendar.png'),
    );
  });
}
