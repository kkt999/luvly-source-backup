import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/fitting_proposal_screen.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_rental_test.dart' show selection;
import 'packages/package_gowns_test.dart' show gownPackage, testGown;

PackageSelection proposed({
  String state = 'AwaitingCustomer',
  bool quote = true,
}) {
  final s = selection();
  s.data.addAll({
    'customerName': 'Jamie',
    'fittingWorkflowVersion': 2,
    'fittingDecisionRevision': 2,
    'fittingQuoteRevision': 1,
    'fittingReady': false,
    'fittingDecision': {
      'mode': 'Attended',
      'outcome': 'Selected',
      'state': state,
      'adjustment': 'Basic',
    },
    'fittingQuote': quote
        ? {
            'revision': 1,
            'state': state == 'AwaitingCustomer' ? 'AwaitingCustomer' : state,
            'baseCents': 89900,
            'extraCents': 10000,
            'totalCents': 99900,
            'note': 'Waist adjustment agreed; final fitting before collection.',
            'lines': [
              {'description': 'Waist adjustment', 'amountCents': 10000},
            ],
          }
        : null,
  });
  return s;
}

HttpPackageApi apiFor(List<http.Request> calls, {bool fail = false}) =>
    HttpPackageApi(
      transport: HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'test-token',
        client: MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode(
              fail ? {'error': 'FITTING_QUOTE_CHANGED'} : {'saved': true},
            ),
            fail ? 409 : 200,
          );
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
      debugShowCheckedModeBanner: false,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'customer acceptance requires explicit agreement and sends only proposal revision',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      var reloads = 0;
      await mount(
        t,
        FittingProposalPanel(
          selection: proposed(),
          api: api,
          staff: false,
          manager: false,
          reload: () => reloads++,
        ),
      );
      expect(find.text('Proposed total: RM 999.00'), findsOneWidget);
      await tap(t, find.text('Review & accept proposal'));
      expect(calls, isEmpty);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Agree to proposal'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.byType(CheckboxListTile));
      await tap(t, find.text('Agree to proposal'));
      expect(calls.length, 1);
      expect(calls.single.url.path, endsWith('/fitting-response'));
      expect(jsonDecode(calls.single.body), {
        'revision': 1,
        'response': 'Accept',
      });
      expect(reloads, 1);
    },
  );
  testWidgets(
    'failed acceptance requires refresh instead of replaying an uncertain action',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls, fail: true);
      addTearDown(api.close);
      await mount(
        t,
        FittingProposalPanel(
          selection: proposed(),
          api: api,
          staff: false,
          manager: false,
          reload: () {},
        ),
      );
      await tap(t, find.text('Review & accept proposal'));
      await tap(t, find.byType(CheckboxListTile));
      await tap(t, find.text('Agree to proposal'));
      expect(find.text('Refresh plan before continuing'), findsOneWidget);
      expect(find.text('Review & accept proposal'), findsNothing);
      expect(calls.length, 1);
    },
  );
  testWidgets(
    'staff cannot accept for customer; stale quote cannot unlock a deposit',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final s = proposed(state: 'Outdated');
      s.data['fittingDecision']['state'] = 'Approved';
      await mount(
        t,
        PackageRentalSummary(
          selection: s,
          api: api,
          staff: true,
          manager: false,
          reload: () {},
        ),
      );
      expect(find.text('Review & accept proposal'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm package rental'),
            )
            .onPressed,
        isNull,
      );
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'quote editor validates details and staff can submit included adjustments only',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await mount(t, const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: FittingQuoteEditor(
            selection: proposed(state: 'QuoteNeeded', quote: false),
            api: api,
            manager: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(t.widget<TextField>(fields.at(1)).enabled, isFalse);
      await tap(t, find.text('Send for customer confirmation'));
      expect(calls, isEmpty);
      await t.enterText(fields.at(0), 'Waist adjustment before collection');
      await t.enterText(
        fields.at(2),
        'Includes the waist adjustment and a follow-up fitting before collection.',
      );
      await tap(t, find.text('Send for customer confirmation'));
      expect(calls.length, 1);
      expect(jsonDecode(calls.single.body)['lines'][0]['amountCents'], 0);
    },
  );
  testWidgets(
    'reselection waits for saved gowns and previews before exact confirmed update',
    (t) async {
      final calls = <http.Request>[];
      final gownsReady = Completer<void>();
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'test-token',
          client: MockClient((r) async {
            calls.add(r);
            if (r.url.path == '/v1/package-gowns') {
              await gownsReady.future;
              return http.Response(
                jsonEncode({
                  'dresses': [
                    {
                      'id': testGown.id,
                      ...testGown.toFields(),
                      'revision': testGown.revision,
                    },
                  ],
                }),
                200,
              );
            }
            if (r.url.path == '/v1/package-availability') {
              return http.Response(
                jsonEncode({
                  'gowns': [
                    {
                      'dressId': testGown.id,
                      'sizes': [
                        {'size': 'S', 'status': 'Available'},
                        {'size': 'M', 'status': 'Available'},
                      ],
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({'totalCents': 84900, 'saved': true}),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      final s = proposed();
      s.data['selectedGowns'] = [
        {'dressId': testGown.id, 'size': 'M'},
      ];
      s.data['selectionRevision'] = 3;
      await mount(t, const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: PackageChoiceScreen(
            package: gownPackage(),
            api: api,
            revising: s,
          ),
        ),
      );
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Loading saved gowns…'),
            )
            .onPressed,
        isNull,
      );
      gownsReady.complete();
      await t.pumpAndSettle();
      await tap(t, find.text('Review selection'));
      await tap(t, find.text('Save package selection'));
      expect(
        find.textContaining('Updated package total: RM 849.00'),
        findsOneWidget,
      );
      var writes = calls.where((r) => r.url.path.endsWith('/revise')).toList();
      expect(writes.length, 1);
      expect(jsonDecode(writes.single.body)['previewOnly'], true);
      await tap(t, find.text('Save changes'));
      writes = calls.where((r) => r.url.path.endsWith('/revise')).toList();
      expect(writes.length, 2);
      expect(
        writes.every(
          (r) => r.url.path == '/v1/package-selections/${s.id}/revise',
        ),
        true,
      );
      final preview = jsonDecode(writes.first.body),
          committed = jsonDecode(writes.last.body);
      expect(committed['requestId'], preview['requestId']);
      expect(committed['expectedTotalCents'], 84900);
      expect(committed['previewOnly'], false);
      expect(committed['revision'], 3);
      expect(committed['gowns'], [
        {'dressId': testGown.id, 'size': 'M', 'revision': testGown.revision},
      ]);
      expect(
        calls.any(
          (r) =>
              r.url.path.contains('checkout') || r.url.path.endsWith('/book'),
        ),
        false,
      );
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('proposal fits $width at $scale', (t) async {
        final calls = <http.Request>[], api = apiFor(calls);
        addTearDown(api.close);
        await mount(
          t,
          RepaintBoundary(
            key: const ValueKey('proposal-capture'),
            child: FittingProposalPanel(
              selection: proposed(),
              api: api,
              staff: false,
              manager: false,
              reload: () {},
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(t.takeException(), isNull);
        if (width == 390 && scale == 1) {
          await expectLater(
            find.byKey(const ValueKey('proposal-capture')),
            matchesGoldenFile('previews/fitting-proposal.png'),
          );
        }
      });
    }
  }
}
