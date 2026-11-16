import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_gowns.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/packages/rental_availability.dart';
import 'package:luvly_app/packages/rental_date_fields.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_gowns_test.dart' show testGown, gownPackage;
import 'packages/package_rental_test.dart' show selection;

Map<String, String> plan([int offset = 0]) {
  final d = DateTime.now().toUtc().add(Duration(days: 10 + offset, hours: 8));
  return {
    'pickupDate': rentalDateText(d),
    'eventDate': rentalDateText(d.add(const Duration(days: 1))),
    'returnDate': rentalDateText(d.add(const Duration(days: 2))),
  };
}

Map<String, dynamic> stock({
  String s = 'Available',
  String m = 'Unavailable',
}) => {
  'gowns': [
    {
      'dressId': testGown.id,
      'sizes': [
        {'size': 'S', 'status': s},
        {'size': 'M', 'status': m},
      ],
    },
  ],
};
http.Response response(Object v, [int status = 200]) =>
    http.Response(jsonEncode(v), status);
HttpPackageApi api(
  List<http.Request> calls, {
  Future<http.Response> Function(http.Request)? handler,
}) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'token',
    client: MockClient((r) async {
      calls.add(r);
      if (handler != null) return handler(r);
      if (r.url.path == '/v1/package-availability') return response(stock());
      if (r.url.path == '/v1/package-gowns') {
        return response({
          'dresses': [
            {
              'id': testGown.id,
              ...testGown.toFields(),
              'revision': testGown.revision,
            },
          ],
        });
      }
      return response({'saved': true});
    }),
  ),
);
Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: RepaintBoundary(key: const ValueKey('page'), child: child),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'dates precede gown selection and incomplete dates never query or save',
    (t) async {
      final calls = <http.Request>[], client = api(calls);
      addTearDown(client.close);
      await mount(t, PackageChoiceScreen(package: gownPackage(), api: client));
      expect(find.text('Choose rental dates'), findsOneWidget);
      expect(find.text('Pickup'), findsNothing);
      final button = find.ancestor(
        of: find.text('Explore wedding gowns'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review selection'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Choose rental dates before choosing gowns.'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'picking dates commits one valid range and returning discards edits',
    (t) async {
      final calls = <http.Request>[], client = api(calls);
      addTearDown(client.close);
      final dates = plan();
      await mount(t, PackageChoiceScreen(package: gownPackage(), api: client));
      await tap(t, 'Choose rental dates');
      expect(find.text('When is your event?'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use these dates'),
            )
            .onPressed,
        isNull,
      );
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime.parse(dates['eventDate']!));
      await t.pumpAndSettle();
      expect(find.text('Suggested rental dates'), findsOneWidget);
      expect(find.text(rentalDateLabel(dates['pickupDate']!)), findsOneWidget);
      expect(find.text(rentalDateLabel(dates['returnDate']!)), findsOneWidget);
      expect(calls, isEmpty);
      await tap(t, 'Use these dates');
      expect(find.text('Your rental dates'), findsOneWidget);
      expect(jsonDecode(calls.single.body)['rentalPlan'], dates);
      await tap(t, 'Change dates');
      expect(find.text('Pickup & return'), findsOneWidget);
      await tap(t, 'Adjust dates');
      await t.tap(find.byKey(ValueKey('Pickup-${dates['eventDate']}')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(
              find.byKey(ValueKey('Return-${dates['returnDate']}')),
            )
            .selected,
        isTrue,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text(rentalDateLabel(dates['pickupDate']!)), findsOneWidget);
      expect(calls, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('same-day event has a valid default at large text', (t) async {
    await mount(
      t,
      const PackageDatesScreen(initialDates: {}, allowedDays: 3),
      width: 320,
      scale: 2,
    );
    final calendar = t.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    calendar.onDateChanged(calendar.firstDate);
    await t.pumpAndSettle();
    expect(
      find.text(rentalDateLabel(rentalDateText(calendar.firstDate))),
      findsNWidgets(2),
    );
    expect(
      find.text(
        rentalDateLabel(
          rentalDateText(DateUtils.addDaysToDate(calendar.firstDate, 1)),
        ),
      ),
      findsOneWidget,
    );
    await tap(t, 'Adjust dates');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'available sizes are selectable; unavailable sizes cannot use selection or size guide bypass',
    (t) async {
      final calls = <http.Request>[], client = api(calls);
      addTearDown(client.close);
      await mount(
        t,
        PackageGownPicker(
          api: client,
          eligibleIds: {testGown.id},
          allowance: 1,
          availability: RentalAvailability(stock()),
          rentalPlan: plan(),
        ),
      );
      expect(find.text('Available · S'), findsOneWidget);
      await t.tap(find.byKey(ValueKey('gown-${testGown.id}')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(ValueKey('size-${testGown.id}-M')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(find.byKey(ValueKey('size-${testGown.id}-M')))
            .onSelected,
        isNull,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Select this gown'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(ValueKey('size-${testGown.id}-S')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Select this gown'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('M · Unavailable for these dates'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'new selection sends dates with available gown in one save and rechecks before confirmation',
    (t) async {
      final calls = <http.Request>[], client = api(calls);
      addTearDown(client.close);
      final dates = plan();
      await mount(
        t,
        PackageChoiceScreen(
          package: gownPackage(),
          api: client,
          initialRentalPlan: dates,
        ),
      );
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
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Package details'), findsOneWidget);
      expect(find.text('${testGown.name} · S'), findsOneWidget);
      expect(calls.any((r) => r.url.path == '/v1/package-selections'), isFalse);
      await tap(t, 'Review selection');
      await tap(t, 'Save package selection');
      final writes = calls
          .where((r) => r.url.path == '/v1/package-selections')
          .toList();
      expect(writes, hasLength(1));
      final body = jsonDecode(writes.single.body);
      expect(body['rentalPlan'], dates);
      expect(body['gowns'].single['size'], 'S');
      final saveIndex = calls.indexOf(writes.single);
      expect(saveIndex, greaterThan(0));
      final lastStockCheck = calls[saveIndex - 1];
      expect(lastStockCheck.url.path, '/v1/package-availability');
      expect(jsonDecode(lastStockCheck.body)['rentalPlan'], dates);
      expect(
        calls.any(
          (r) =>
              r.url.path.contains('checkout') || r.url.path.endsWith('/book'),
        ),
        false,
      );
    },
  );
  testWidgets(
    'unavailable saved size and failed availability cannot advance to review',
    (t) async {
      final calls = <http.Request>[];
      var fail = false;
      final client = api(
        calls,
        handler: (r) async {
          if (r.url.path == '/v1/package-gowns') {
            return response({
              'dresses': [
                {
                  'id': testGown.id,
                  ...testGown.toFields(),
                  'revision': testGown.revision,
                },
              ],
            });
          }
          return fail
              ? response({'error': 'SERVICE_UNAVAILABLE'}, 503)
              : response(stock());
        },
      );
      addTearDown(client.close);
      final saved = selection();
      saved.data['selectedGowns'] = [
        {'dressId': testGown.id, 'size': 'M'},
      ];
      await mount(
        t,
        PackageChoiceScreen(
          package: gownPackage(),
          api: client,
          revising: saved,
          initialRentalPlan: plan(),
        ),
      );
      await tap(t, 'Review selection');
      expect(
        find.textContaining('A selected gown or size is not available'),
        findsOneWidget,
      );
      expect(find.text('Save package selection'), findsNothing);
      fail = true;
      await tap(t, 'Review selection');
      expect(find.text('Save package selection'), findsNothing);
      expect(calls.any((r) => r.url.path.endsWith('/revise')), false);
    },
  );
  testWidgets(
    'out of order availability response cannot replace the newest rental date check',
    (t) async {
      final calls = <http.Request>[],
          first = Completer<http.Response>(),
          second = Completer<http.Response>();
      final client = api(
        calls,
        handler: (r) async => calls.length == 1 ? first.future : second.future,
      );
      addTearDown(client.close);
      await mount(t, PackageChoiceScreen(package: gownPackage(), api: client));
      await tap(t, 'Choose rental dates');
      Future<void> pickDates(Map<String, String> dates) async {
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .onDateChanged(DateTime.parse(dates['eventDate']!));
        await t.pumpAndSettle();
        await t.tap(find.text('Use these dates'));
      }

      await pickDates(plan());
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      final edit = find.text('Change dates');
      await t.ensureVisible(edit);
      await t.pump();
      await t.tap(edit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      await tap(t, 'Wedding / event');
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime.parse(plan(2)['eventDate']!));
      await t.pumpAndSettle();
      await tap(t, 'OK');
      await t.tap(find.text('Use these dates'));
      await t.pump();
      second.complete(response(stock(s: 'Unavailable', m: 'Unavailable')));
      await t.pumpAndSettle();
      first.complete(response(stock()));
      await t.pumpAndSettle();
      // Opening the collection must use a fresh snapshot, never the older available result.
      expect(calls, hasLength(2));
      expect(jsonDecode(calls.last.body)['rentalPlan'], plan(2));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'known plan conflict stops fitting-choice writes and offers gown reselection',
    (t) async {
      final calls = <http.Request>[],
          client = api(
            calls,
            handler: (r) async => r.method == 'GET'
                ? response({'visits': []})
                : response({
                    'available': false,
                    'items': [
                      {
                        'name': 'Ivory gown',
                        'size': 'M',
                        'status': 'Unavailable',
                      },
                    ],
                  }),
          );
      addTearDown(client.close);
      await mount(
        t,
        PackageRentalScreen(
          selection: selection(),
          api: client,
          onBookFitting: (_) async => true,
        ),
      );
      await tap(t, 'Choose fitting time');
      final writes = calls.where((request) => request.method == 'POST');
      expect(writes, hasLength(1));
      expect(writes.single.url.path, endsWith('/check-plan'));
      expect(find.text('Change gown selection'), findsOneWidget);
      expect(
        find.textContaining('Unavailable for these dates'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('date-first page fits $width at large text', (t) async {
      final calls = <http.Request>[], client = api(calls);
      addTearDown(client.close);
      await mount(
        t,
        PackageChoiceScreen(package: gownPackage(), api: client),
        width: width,
        scale: 2,
      );
      await t.drag(find.byType(ListView).first, const Offset(0, -500));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('long package content expands and saved dates fit larger text', (
    t,
  ) async {
    final calls = <http.Request>[], client = api(calls);
    addTearDown(client.close);
    final description = List.filled(
      12,
      'Choose your favourite details for the ceremony and reception.',
    ).join(' ');
    final package = BridalPackage.fromJson({
      ...gownPackage().toJson(),
      'name': 'A Wedding Package with a Long Name',
      'description': description,
    });
    await mount(
      t,
      PackageChoiceScreen(
        package: package,
        api: client,
        initialRentalPlan: plan(),
      ),
      width: 320,
      scale: 2,
    );
    expect(t.widget<Text>(find.text(description)).maxLines, 2);
    await tap(t, 'Read more');
    expect(t.widget<Text>(find.text(description)).maxLines, isNull);
    await tap(t, 'Read less');
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.text(description)).maxLines, 2);
    await t.scrollUntilVisible(
      find.text('Rental dates are subject to staff confirmation.'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('date-first mobile preview', (t) async {
    final calls = <http.Request>[], client = api(calls);
    addTearDown(client.close);
    final sample = BridalPackage.fromJson({
      ...gownPackage().toJson(),
      'id': 'bridal-essentials',
      'name': 'Bridal Essentials',
      'basePriceCents': 89900,
      'description':
          'A wedding gown rental with a personal fitting and your choice of '
          'accessories. Add an extra fitting or rental day if you need more time.',
    });
    await mount(
      t,
      PackageChoiceScreen(
        package: sample,
        api: client,
        initialRentalPlan: const {
          'pickupDate': '2026-10-30',
          'eventDate': '2026-10-31',
          'returnDate': '2026-11-01',
        },
      ),
    );
    final cover = find.byType(Image).first;
    await t.runAsync(
      () => precacheImage(t.widget<Image>(cover).image, t.element(cover)),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('page')),
      matchesGoldenFile('previews/date-first-mobile.png'),
    );
  });
}
