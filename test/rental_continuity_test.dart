import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/packages/rental_date_fields.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/bookings/booking_screens.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'date_first_gowns_test.dart' show plan;
import 'packages/package_gowns_test.dart' show testGown, gownPackage;
import 'packages/package_rental_test.dart' show selection;

const savedDates = {
  'eventDate': '2026-11-11',
  'pickupDate': '2026-11-10',
  'returnDate': '2026-11-12',
};
http.Response json(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
Future<void> tap(WidgetTester t, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(target.first);
  await t.pumpAndSettle();
  await t.tap(target.first);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  Widget page, {
  double width = 390,
  double scale = 1,
  bool settle = true,
}) async {
  viewport(t, Size(width, 1000));
  await fonts();
  final model = AppModel()
    ..accountId = 'bride'
    ..name = 'Customer'
    ..phone = '0123456789';
  addTearDown(model.dispose);
  await t.pumpWidget(
    AppScope(
      model: model,
      child: MaterialApp(
        theme: luvlyTheme,
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: RepaintBoundary(key: const ValueKey('screen'), child: page),
      ),
    ),
  );
  if (settle) await t.pumpAndSettle();
}

HttpPackageApi transport(
  List<http.Request> calls, {
  Future<http.Response> Function(http.Request)? handler,
}) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'token',
    client: MockClient((r) async {
      calls.add(r);
      if (handler != null) return handler(r);
      if (r.url.path.endsWith('/completed-fitting')) {
        return json({'visits': []});
      }
      if (r.url.path.endsWith('/check-plan')) {
        return json({'available': true, 'items': []});
      }
      return json({'saved': true, 'revision': 3, 'fittingChoiceRevision': 1});
    }),
  ),
);

void main() {
  testWidgets(
    'completed fittings stay disabled while checking or unavailable',
    (t) async {
      final calls = <http.Request>[];
      final initial = Completer<http.Response>();
      final api = transport(
        calls,
        handler: (r) async =>
            calls.length == 1 ? initial.future : json({'visits': []}),
      );
      addTearDown(api.close);
      await mount(
        t,
        PackageRentalScreen(
          selection: selection()..data['rentalPlan'] = savedDates,
          api: api,
          onBookFitting: (_) async => true,
        ),
        settle: false,
      );
      await t.pump();
      final previous = find.ancestor(
        of: find.text('Use a completed fitting'),
        matching: find.byWidgetPredicate((widget) => widget is RadioListTile),
      );
      expect(t.widget<RadioListTile>(previous).enabled, isFalse);
      expect(find.text('Checking your eligible fittings…'), findsOneWidget);
      expect(find.text('RM 50.00 · 60-minute fitting'), findsOneWidget);
      expect(
        find.textContaining('eligible fee can be credited once'),
        findsOneWidget,
      );
      initial.complete(json({'error': 'NETWORK_FAILURE'}, 503));
      await t.pumpAndSettle();
      expect(
        find.text('We couldn’t check your previous fittings.'),
        findsOneWidget,
      );
      await tap(t, 'Retry fitting check');
      expect(
        find.textContaining('No eligible fitting for these dates'),
        findsOneWidget,
      );
      expect(t.widget<RadioListTile>(previous).enabled, isFalse);
      expect(
        t
            .widgetList<RadioListTile>(
              find.byWidgetPredicate((widget) => widget is RadioListTile),
            )
            .where((r) => r.selected),
        hasLength(1),
      );
      expect(calls.map((r) => r.method), ['GET', 'GET']);
    },
  );

  testWidgets('confirmed visit prevents requesting to rent without a fitting', (
    t,
  ) async {
    final calls = <http.Request>[], api = transport(calls);
    addTearDown(api.close);
    await mount(
      t,
      PackageRentalScreen(
        selection: selection()..data['rentalPlan'] = savedDates,
        api: api,
      ),
    );
    final skip = find.ancestor(
      of: find.text('Rent without a fitting'),
      matching: find.byWidgetPredicate((widget) => widget is RadioListTile),
    );
    expect(t.widget<RadioListTile>(skip).enabled, isFalse);
    expect(
      find.textContaining('Cancel your active appointment'),
      findsOneWidget,
    );
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets(
    'changing dates rechecks the selected previous visit after saving',
    (t) async {
      final calls = <http.Request>[];
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final today = DateTime(now.year, now.month, now.day);
      final event = today.add(const Duration(days: 14));
      final initial = {
        'eventDate': rentalDay(event),
        'pickupDate': rentalDay(event.subtract(const Duration(days: 1))),
        'returnDate': rentalDay(event.add(const Duration(days: 1))),
      };
      final attended = today
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final api = transport(
        calls,
        handler: (r) async {
          if (r.url.path.endsWith('/completed-fitting')) {
            return json({
              'visits': [
                if (calls.where((r) => r.method == 'GET').length == 1)
                  {'id': 'first', 'attendedAt': attended, 'creditCents': 5000},
              ],
            });
          }
          if (r.url.path.endsWith('/check-plan')) {
            return json({'available': true, 'items': []});
          }
          return json({'revision': 3});
        },
      );
      addTearDown(api.close);
      final s = selection()
        ..data['rentalPlan'] = initial
        ..data['appointments'] = [];
      await mount(t, PackageRentalScreen(selection: s, api: api));
      await tap(t, 'Use a completed fitting');
      await tap(t, 'Select completed fitting');
      await tap(t, paymentDateLabel(attended));
      expect(find.text('Continue with selected fitting'), findsOneWidget);
      await tap(t, 'Change dates');
      await tap(t, 'Return date');
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(event);
      await t.pumpAndSettle();
      await tap(t, 'OK');
      expect(find.text('Continue with selected fitting'), findsNothing);
      expect(calls.where((r) => r.method == 'GET'), hasLength(1));
      await tap(t, 'Save rental dates');
      expect(
        find.textContaining('No eligible fitting for these dates'),
        findsOneWidget,
      );
      final next = find.widgetWithText(
        FilledButton,
        'Select completed fitting',
      );
      expect(t.widget<FilledButton>(next).onPressed, isNull);
      expect(calls.where((r) => r.method == 'GET'), hasLength(2));
      final write = calls.singleWhere((r) => r.url.path.endsWith('/plan'));
      expect(jsonDecode(write.body)['returnDate'], rentalDay(event));
      expect(
        calls.where((r) => r.url.path.endsWith('/fitting-choice')),
        isEmpty,
      );
    },
  );

  testWidgets('saved dates are a summary and only become editable on request', (
    t,
  ) async {
    final calls = <http.Request>[], api = transport(calls);
    addTearDown(api.close);
    final s = selection()..data['rentalPlan'] = savedDates;
    await mount(
      t,
      PackageRentalScreen(
        selection: s,
        api: api,
        onBookFitting: (_) async => true,
      ),
    );
    expect(find.text('Arrange your fitting'), findsOneWidget);
    expect(find.byType(PackageRentalDatesCard), findsOneWidget);
    expect(find.text('Choose a date'), findsNothing);
    expect(find.text('Wedding / event date'), findsOneWidget);
    expect(find.text('11 Nov 2026'), findsOneWidget);
    await tap(t, 'Change dates');
    expect(find.byType(PackageRentalDatesCard), findsNothing);
    expect(find.text('Wedding / event date'), findsOneWidget);
    expect(find.text('11 Nov 2026'), findsOneWidget);
    await tap(t, 'Keep saved dates');
    expect(find.byType(PackageRentalDatesCard), findsOneWidget);
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets(
    'continuing an unchanged plan neither rewrites dates nor creates another selection',
    (t) async {
      final calls = <http.Request>[], api = transport(calls);
      addTearDown(api.close);
      Map<String, String>? received;
      final s = selection()..data['rentalPlan'] = savedDates;
      await mount(
        t,
        PackageRentalScreen(
          selection: s,
          api: api,
          onBookFitting: (d) async {
            received = d;
            return true;
          },
        ),
      );
      await tap(t, 'Choose fitting time');
      expect(received, savedDates);
      expect(calls.where((r) => r.method == 'POST').map((r) => r.url.path), [
        '/v1/package-selections/selection/check-plan',
        '/v1/package-selections/selection/fitting-choice',
      ]);
    },
  );

  testWidgets(
    'explicit date editing does not change fitting preference or open a new booking',
    (t) async {
      final calls = <http.Request>[], api = transport(calls);
      addTearDown(api.close);
      final s = selection()..data['rentalPlan'] = savedDates;
      await mount(
        t,
        PackageRentalScreen(selection: s, api: api, editDates: true),
      );
      expect(find.text('How would you like to proceed?'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save date changes'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Return date');
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(2026, 11, 11));
      await t.pumpAndSettle();
      await tap(t, 'OK');
      await tap(t, 'Save date changes');
      final writes = calls
          .where((r) => !r.url.path.endsWith('/check-plan'))
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.url.path, endsWith('/plan'));
      expect(jsonDecode(writes.single.body)['returnDate'], '2026-11-11');
      expect(jsonDecode(writes.single.body)['revision'], 2);
    },
  );

  testWidgets(
    'legacy undated plan explains the missing step without borrowing another plan dates',
    (t) async {
      final calls = <http.Request>[], api = transport(calls);
      addTearDown(api.close);
      final s = selection()..data.remove('rentalPlan');
      await mount(t, PackageRentalScreen(selection: s, api: api));
      expect(
        find.textContaining('This saved package has no rental dates yet'),
        findsOneWidget,
      );
      expect(find.text('Choose a date'), findsNWidgets(3));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save fitting preference'),
            )
            .onPressed,
        isNull,
      );
      expect(calls, isEmpty);
    },
  );

  testWidgets(
    'complete catalogue to fitting path keeps the exact new plan even with an older focused same-package plan',
    (t) async {
      final calls = <http.Request>[];
      Map<String, dynamic>? created;
      final old = {
        ...selection().data,
        'id': 'older-plan',
        'packageId': gownPackage().id,
      }..remove('rentalPlan');
      final api = transport(
        calls,
        handler: (r) async {
          if (r.url.path == '/v1/packages') {
            return json({
              'packages': [gownPackage().toJson()],
            });
          }
          if (r.url.path == '/v1/package-selections' && r.method == 'GET') {
            return json({
              'selections': [?created, old],
            });
          }
          if (r.url.path == '/v1/package-gowns') {
            return json({
              'dresses': [
                {
                  'id': testGown.id,
                  ...testGown.toFields(),
                  'revision': testGown.revision,
                },
              ],
            });
          }
          if (r.url.path == '/v1/package-availability') {
            return json({
              'gowns': [
                {
                  'dressId': testGown.id,
                  'sizes': [
                    {'size': 'S', 'status': 'Available'},
                    {'size': 'M', 'status': 'Available'},
                  ],
                },
              ],
            });
          }
          if (r.url.path == '/v1/package-selections' && r.method == 'POST') {
            final body = jsonDecode(r.body);
            created = {
              ...selection().data,
              'id': 'new-plan',
              'packageId': gownPackage().id,
              'rentalPlan': body['rentalPlan'],
              'rentalPlanRevision': 1,
              'selectedGowns': [
                {'dressId': testGown.id, 'name': testGown.name, 'size': 'S'},
              ],
              'services': gownPackage().services
                  .map((v) => v.toJson())
                  .toList(),
              'appointments': [],
            };
            return json(created!, 201);
          }
          if (r.url.path.endsWith('/check-plan')) {
            return json({'available': true, 'items': []});
          }
          if (r.url.path.endsWith('/completed-fitting')) {
            return json({'visits': []});
          }
          if (r.url.path.endsWith('/fitting-choice')) {
            return json({'fittingChoiceRevision': 1});
          }
          return json({'saved': true});
        },
      );
      addTearDown(api.close);
      await mount(
        t,
        LivePackageScreen(api: api, initialSelectionId: 'older-plan'),
      );
      await tap(t, 'Explore package');
      final dates = plan();
      await tap(t, 'Choose rental dates');
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime.parse(dates['eventDate']!));
      await t.pumpAndSettle();
      await tap(t, 'Use these dates');
      await tap(t, 'Explore wedding gowns');
      await t.tap(find.byKey(ValueKey('gown-${testGown.id}')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(ValueKey('size-${testGown.id}-S')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('size-${testGown.id}-S')));
      await t.pumpAndSettle();
      await tap(t, 'Select this gown');
      await tap(t, 'Use selected gowns (1/1)');
      await tap(t, 'Review selection');
      await tap(t, 'Save package selection');
      expect(find.byType(PackageRentalScreen), findsOneWidget);
      final next = t.widget<PackageRentalScreen>(
        find.byType(PackageRentalScreen),
      );
      expect(next.selection.id, 'new-plan');
      expect(next.selection.data['rentalPlan'], dates);
      expect(find.text('Choose a date'), findsNothing);
      expect(find.byType(PackageRentalDatesCard), findsOneWidget);
      await tap(t, 'Choose fitting time');
      expect(find.byType(BookingRequestForm), findsOneWidget);
      final form = t.widget<BookingRequestForm>(
        find.byType(BookingRequestForm),
      );
      expect(
        form.latestAppointmentDay,
        DateUtils.addDaysToDate(DateTime.parse(dates['pickupDate']!), -1),
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(PackageRentalScreen), findsOneWidget);
      expect(find.byType(BookingRequestForm), findsNothing);
      expect(find.text('Choose fitting time'), findsOneWidget);
      expect(
        t
            .widget<PackageRentalDatesCard>(find.byType(PackageRentalDatesCard))
            .dates,
        dates,
      );
      expect(calls.any((r) => r.url.path.endsWith('/book')), isFalse);
      expect(
        calls.where(
          (r) => r.url.path == '/v1/package-selections' && r.method == 'POST',
        ),
        hasLength(1),
      );
      expect(calls.any((r) => r.url.path.endsWith('/plan')), false);
      expect(
        calls.any(
          (r) => r.url.path.contains('older-plan/') && r.method == 'POST',
        ),
        false,
      );
      expect(t.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('fitting summary fits $width at large text', (t) async {
      final calls = <http.Request>[], api = transport(calls);
      addTearDown(api.close);
      final s = selection()
        ..data['rentalPlan'] = savedDates
        ..data['selectedGowns'] = [
          {
            'dressId': 'gown',
            'name': 'The Ivory Cathedral Bridal Gown with a Long Train',
            'size': 'XL',
          },
        ];
      t.view.viewPadding = const FakeViewPadding(bottom: 22);
      t.view.padding = const FakeViewPadding(bottom: 22);
      addTearDown(t.view.resetViewPadding);
      addTearDown(t.view.resetPadding);
      await mount(
        t,
        PackageRentalScreen(
          selection: s,
          api: api,
          onBookFitting: (_) async => true,
        ),
        width: width,
        scale: 2,
      );
      expect(find.text('Selected size: XL'), findsOneWidget);
      expect(
        find.text('The Ivory Cathedral Bridal Gown with a Long Train'),
        findsOneWidget,
      );
      await t.drag(find.byType(ListView).first, const Offset(0, -600));
      await t.pumpAndSettle();
      expect(find.text('Choose fitting time').hitTestable(), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Choose fitting time');
      expect(t.getBottomLeft(button).dy, lessThanOrEqualTo(978));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('fitting continuation preview', (t) async {
    final calls = <http.Request>[];
    final api = transport(
      calls,
      handler: (_) async => json({
        'visits': [
          {'id': 'visit', 'attendedAt': 1792116000000, 'creditCents': 5000},
        ],
      }),
    );
    addTearDown(api.close);
    await mount(
      t,
      PackageRentalScreen(
        selection: selection()
          ..data['rentalPlan'] = savedDates
          ..data['appointments'] = [],
        api: api,
        onBookFitting: (_) async => true,
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('screen')),
      matchesGoldenFile('previews/fitting-continuation-2065.png'),
    );
  });
}
