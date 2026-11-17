import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/packages/fitting_result_screen.dart';
import 'package:luvly_app/packages/fitting_proposal_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'packages/package_rental_test.dart' show selection;
import 'checkout_redesign_test.dart' show fonts, viewport;

HttpPackageApi apiFor(List<http.Request> calls) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'test-token',
    client: MockClient((r) async {
      calls.add(r);
      if (r.url.path.endsWith('/completed-fitting')) {
        return http.Response(jsonEncode({'visits': []}), 200);
      }
      return http.Response(
        jsonEncode({
          'available': true,
          'items': [],
          'availability': [
            {'remaining': 1},
          ],
        }),
        200,
      );
    }),
  ),
);
Future<void> show(WidgetTester t, Widget child, {double scale = 1}) =>
    t.pumpWidget(
      MaterialApp(
        theme: luvlyTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: child,
      ),
    );
Future<void> scrollTo(WidgetTester t, String label) async {
  await t.scrollUntilVisible(
    find.text(label),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('older servers still let staff confirm makeup timing', (t) async {
    viewport(t, const Size(1150, 1000));
    final api = HttpPackageApi(
      transport: HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'test-token',
        client: MockClient(
          (_) async => http.Response('{"error":"NOT_FOUND"}', 404),
        ),
      ),
    );
    addTearDown(api.close);
    final selected = selection();
    selected.data['services'] = [
      const PackageServiceItem(
        id: 'makeup-hair',
        name: 'Bridal makeup',
        description: '',
        kind: 'Required',
        priceCents: 0,
      ).toJson(),
    ];
    selected.data['fittingDecision'] = {'adjustment': 'None'};
    await show(
      t,
      FittingQuoteEditor(selection: selected, api: api, manager: false),
    );
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Bridal makeup'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'makeup proposal reuses the wedding date and selected trial booking',
    (t) async {
      viewport(t, const Size(1150, 1000));
      final calls = <http.Request>[];
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'test-token',
          client: MockClient((request) async {
            calls.add(request);
            return http.Response(
              jsonEncode(
                request.method == 'GET'
                    ? {
                        'artists': [
                          {'id': 'artist', 'name': 'Test Artist'},
                        ],
                        'trials': [
                          {
                            'id': 'trial',
                            'day': '2026-10-15',
                            'minuteOfDay': 840,
                            'artistName': 'Test Artist',
                            'revision': 3,
                          },
                        ],
                      }
                    : {},
              ),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      final formal = const PackageServiceItem(
        id: 'formal',
        name: 'Bridal makeup',
        description: '',
        kind: 'Required',
        priceCents: 0,
        serviceType: PackageServiceType.makeupHair,
      ).toJson();
      final trial = const PackageServiceItem(
        id: 'trial-service',
        name: 'Makeup trial',
        description: '',
        kind: 'Add-on',
        priceCents: 20000,
        serviceType: PackageServiceType.makeupTrial,
      ).toJson();
      final selected = selection();
      selected.data['services'] = [formal, trial];
      selected.data['fittingDecision'] = {'adjustment': 'None'};
      selected.data['fittingQuote'] = {
        'servicePlan': [
          {
            'serviceId': 'formal',
            'timing': 'Previously selected',
            'schedule': {'artistId': 'artist', 'minuteOfDay': 540},
          },
        ],
      };
      await show(
        t,
        FittingQuoteEditor(selection: selected, api: api, manager: false),
      );
      await t.pumpAndSettle();
      expect(find.text('Makeup & hair'), findsOneWidget);
      expect(find.text('17 Oct 2026'), findsOneWidget);
      expect(find.text('09:00 MYT'), findsOneWidget);
      await t.tap(find.text('Enter agreed time'));
      await t.pumpAndSettle();
      await t.tap(find.text('15 Oct 2026 · 14:00 MYT · Test Artist').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextField),
        'The makeup arrangements are confirmed.',
      );
      await t.tap(find.text('Send for customer confirmation'));
      await t.pumpAndSettle();
      expect(calls.first.url.path, endsWith('/fitting-makeup-options'));
      final body = jsonDecode(calls.last.body) as Map;
      expect(body['serviceConfirmations'], [
        {'serviceId': 'formal', 'artistId': 'artist', 'minuteOfDay': 540},
        {
          'serviceId': 'trial-service',
          'appointmentId': 'trial',
          'appointmentRevision': 3,
        },
      ]);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'no fitting requires explicit consent and saves choice without opening booking',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      var bookings = 0;
      await show(
        t,
        PackageRentalScreen(
          selection: selection()..data['appointments'] = [],
          api: api,
          onBookFitting: (_) async {
            bookings++;
            return true;
          },
        ),
      );
      await t.pumpAndSettle();
      await scrollTo(t, 'Rent without a fitting');
      await t.tap(find.text('Rent without a fitting'));
      await t.pumpAndSettle();
      final review = find.widgetWithText(FilledButton, 'Request staff review');
      expect(t.widget<FilledButton>(review).onPressed, isNull);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(find.textContaining('60-minute fitting'), findsNothing);
      await t.scrollUntilVisible(
        find.byType(CheckboxListTile),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(review);
      await t.pumpAndSettle();
      final writes = calls.where((r) => r.method == 'POST').toList();
      expect(writes.length, 2);
      expect(writes[0].url.path, endsWith('/check-plan'));
      expect(writes[1].url.path, endsWith('/fitting-choice'));
      expect(jsonDecode(writes[1].body), {
        'mode': 'SkipFitting',
        'accepted': true,
        'revision': 0,
      });
      expect(bookings, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'staff cannot submit attendance without a real-service attestation and note',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await show(t, FittingResultScreen(selection: selection(), api: api));
      await t.pumpAndSettle();
      await scrollTo(t, 'Save fitting outcome');
      await t.tap(find.text('Save fitting outcome'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(
        find.textContaining('Select the visit, add a clear'),
        findsOneWidget,
      );
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('fitting-visit')),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('fitting-visit')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fitting-visit')));
      await t.pumpAndSettle();
      await t.tap(find.text(planningTime(1792116000000)).last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('fitting-notes')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended and is happy with the selected gown.',
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await scrollTo(t, 'Save fitting outcome');
      await t.tap(find.text('Save fitting outcome'));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      final body = jsonDecode(calls.single.body);
      expect(body['mode'], 'Attended');
      expect(body['confirmed'], true);
      expect(body.containsKey('actualAt'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'approved no-fitting deposit does not require a fabricated appointment',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final s = selection();
      s.data.addAll({
        'appointments': [],
        'paymentPolicyVersion': 1,
        'fittingChoice': {'mode': 'SkipFitting', 'accepted': true},
        'fittingDecision': {'mode': 'Waived', 'state': 'Approved'},
        'fittingDecisionRevision': 2,
      });
      await show(t, PackageRentalScreen(selection: s, api: api, staff: true));
      await t.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await scrollTo(t, 'Confirm & hold for 15 minutes');
      await t.tap(find.text('Confirm & hold for 15 minutes'));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      final body = jsonDecode(calls.single.body);
      expect(body['appointmentId'], '');
      expect(body['depositCents'], 44950);
      expect(body['fittingRevision'], 2);
      expect(t.takeException(), isNull);
    },
  );
  test('no-fitting receipt must have an authentic package reference', () {
    final data = {
      'id': 'b' * 32,
      'title': 'Package deposit',
      'appointmentId': '',
      'packageSelectionId': 'a' * 32,
      'environment': 'sandbox',
      'amountCents': 44950,
      'state': 'Quoted',
    };
    expect(SandboxInvoice.fromJson(data).packageSelectionId, 'a' * 32);
    expect(
      () => SandboxInvoice.fromJson({...data, 'packageSelectionId': null}),
      throwsA(isA<PaymentFailure>()),
    );
    expect(planningStatus('Waived'), 'No fitting · approved');
    expect(planningDone('Waived'), true);
    expect(planningDone('WaiverRequested'), false);
  });
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final waived in [false, true]) {
        testWidgets('fitting record fits $width / $scale / waived=$waived', (
          t,
        ) async {
          viewport(t, Size(width, 900));
          await fonts();
          final calls = <http.Request>[], api = apiFor(calls);
          addTearDown(api.close);
          final s = selection();
          if (waived) {
            s.data['fittingChoice'] = {'mode': 'SkipFitting', 'accepted': true};
          }
          await show(
            t,
            RepaintBoundary(
              key: const ValueKey('fitting-preview'),
              child: FittingResultScreen(selection: s, api: api),
            ),
            scale: scale,
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (width == 390 && scale == 1) {
            await expectLater(
              find.byKey(const ValueKey('fitting-preview')),
              matchesGoldenFile(
                'goldens/fitting-${waived ? 'waiver' : 'attended'}.png',
              ),
            );
          }
          await scrollTo(
            t,
            waived ? 'Approve no-fitting request' : 'Save fitting outcome',
          );
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
