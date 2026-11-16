import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/rental_date_change_screen.dart';
import 'package:luvly_app/packages/rental_handover_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fitting_workflow_test.dart' show show, scrollTo;

String day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime visualRentalNow() => DateTime.utc(2026, 10, 17, 4);

Map<String, dynamic> rental({DateTime? at}) {
  final now = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 8)),
      today = DateTime(now.year, now.month, now.day);
  return {
    'id': 'a' * 32,
    'packageSelectionId': 'b' * 32,
    'eventDate': day(today.add(const Duration(days: 12))),
    'pickupDate': day(today.add(const Duration(days: 11))),
    'returnDate': day(today.add(const Duration(days: 13))),
    'gowns': [
      {'name': 'Ivory gown', 'size': 'M'},
    ],
    'accessories': [],
    'balanceCents': 44950,
    'securityCents': 30000,
    'paymentState': 'Paid',
    'securityState': 'Paid',
  };
}

HttpPaymentApi apiFor(
  List<http.Request> calls, {
  bool allowed = true,
  bool failConfirm = false,
}) => HttpPaymentApi(
  baseUrl: 'https://example.com',
  token: () async => 'token',
  client: MockClient((r) async {
    calls.add(r);
    final body = jsonDecode(r.body);
    if (body['previewOnly'] == true) {
      return http.Response(
        jsonEncode({
          'canConfirm': allowed,
          'rentalDays': allowed ? 3 : 4,
          'allowedRentalDays': 3,
          'extraDaysRequired': allowed ? 0 : 1,
          'availableAgain': '2026-11-02',
          'additionalChargeCents': allowed ? 0 : null,
        }),
        200,
      );
    }
    if (failConfirm) {
      return http.Response(
        jsonEncode({'error': 'RENTAL_STOCK_UNAVAILABLE'}),
        409,
      );
    }
    return http.Response(
      jsonEncode({
        ...rental(),
        'pickupDate': body['pickupDate'],
        'returnDate': body['returnDate'],
        'dateRevision': 1,
      }),
      200,
    );
  }),
);
Future<void> preview(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.byType(TextField),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.enterText(
    find.byType(TextField),
    'Customer requested an earlier pickup and agreed to the revised return date.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await scrollTo(t, 'Check dates & availability');
  await t.tap(find.text('Check dates & availability'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'preview does not save; consent required; confirm carries dates, revision and stable request only',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final r = rental();
      await show(t, RentalDateChangeScreen(rental: r, api: api));
      await t.pumpAndSettle();
      await t.tap(find.text('New pickup date'));
      await t.pumpAndSettle();
      final newPickup = DateTime.parse(
        r['pickupDate'],
      ).subtract(const Duration(days: 1));
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(newPickup);
      await t.pump();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('New return date'));
      await t.pumpAndSettle();
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime.parse(r['eventDate']));
      await t.pump();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await preview(t);
      expect(calls.length, 1);
      expect(jsonDecode(calls.first.body)['previewOnly'], true);
      await scrollTo(t, 'Confirm agreed date change');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm agreed date change'),
            )
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await scrollTo(t, 'Confirm agreed date change');
      await t.tap(find.text('Confirm agreed date change'));
      await t.pumpAndSettle();
      expect(calls.length, 2);
      final body = jsonDecode(calls.last.body);
      expect(body['customerAgreed'], true);
      expect(body['pickupDate'], day(newPickup));
      expect(body['revision'], 0);
      expect(body.containsKey('eventDate'), false);
      expect(body.containsKey('amountCents'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('extra days show no invented price and cannot be confirmed', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    final calls = <http.Request>[], api = apiFor(calls, allowed: false);
    addTearDown(api.close);
    await show(t, RentalDateChangeScreen(rental: rental(), api: api));
    await t.pumpAndSettle();
    await preview(t);
    await scrollTo(t, 'Additional rental days need review');
    expect(find.textContaining('1 extra day(s)'), findsOneWidget);
    expect(
      find.textContaining('No extra fee has been quoted or charged.'),
      findsOneWidget,
    );
    expect(find.text('Confirm agreed date change'), findsNothing);
    expect(calls.length, 1);
  });
  testWidgets(
    'missing customer discussion note blocks before contacting backend',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await show(t, RentalDateChangeScreen(rental: rental(), api: api));
      await t.pumpAndSettle();
      await scrollTo(t, 'Check dates & availability');
      await t.tap(find.text('Check dates & availability'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.textContaining('Add a clear reason'), findsOneWidget);
    },
  );
  testWidgets(
    'future handover disabled with clear amendment entry; not an early-collection bypass',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await show(t, RentalHandoverScreen(rental: rental(), api: api));
      await t.pumpAndSettle();
      await scrollTo(t, 'Confirm items collected');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm items collected'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Adjust pickup & return dates'), findsOneWidget);
      expect(calls, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'changed stock after preview is surfaced; retry uses same frozen identity and no auto collection',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls, failConfirm: true);
      addTearDown(api.close);
      await show(t, RentalDateChangeScreen(rental: rental(), api: api));
      await t.pumpAndSettle();
      await preview(t);
      await t.scrollUntilVisible(
        find.byType(CheckboxListTile),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await scrollTo(t, 'Confirm agreed date change');
      await t.tap(find.text('Confirm agreed date change'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm agreed date change'));
      await t.pumpAndSettle();
      expect(calls.length, 3);
      expect(calls[1].body, calls[2].body);
      expect(calls.every((r) => r.url.path.endsWith('/change-dates')), true);
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('date amendment layout $width / $scale', (t) async {
        viewport(t, Size(width, 900));
        await fonts();
        final calls = <http.Request>[], api = apiFor(calls);
        addTearDown(api.close);
        await show(
          t,
          RepaintBoundary(
            key: const ValueKey('date-preview'),
            child: RentalDateChangeScreen(
              rental: rental(at: visualRentalNow()),
              api: api,
              now: visualRentalNow,
            ),
          ),
          scale: scale,
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (width == 390 && scale == 1) {
          await expectLater(
            find.byKey(const ValueKey('date-preview')),
            matchesGoldenFile('goldens/rental-date-change.png'),
          );
        }
        await preview(t);
        await scrollTo(t, 'Confirm agreed date change');
        expect(t.takeException(), isNull);
      });
    }
  }
}
