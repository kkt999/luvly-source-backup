import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/fitting_result_screen.dart';
import 'package:luvly_app/packages/fitting_workbench.dart';
import 'package:luvly_app/packages/fitting_assessment.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_rental_test.dart' show selection;

final visitAt = DateTime.utc(2026, 10, 22, 6).millisecondsSinceEpoch;

HttpPackageApi mockApi(
  List<http.Request> calls, {
  Map<String, dynamic> feeChanges = const {},
  bool feeFailed = false,
}) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'staff',
    client: MockClient((r) async {
      calls.add(r);
      if (feeFailed && r.url.path.contains('/invoices/')) {
        return http.Response('{"error":"TRY_LATER"}', 503);
      }
      return http.Response(
        jsonEncode(
          r.url.path.endsWith('/package-gowns')
              ? {'dresses': []}
              : r.url.path.contains('/invoices/')
              ? {
                  'purpose': 'FittingFee',
                  'appointmentId': 'appointment',
                  'state': 'SandboxPaid',
                  'environment': 'sandbox',
                  'amountCents': 5000,
                  'invoiceNo': 'TP260001',
                  ...feeChanges,
                }
              : {'saved': true},
        ),
        200,
      );
    }),
  ),
);
PackageSelection customer() {
  final s = selection();
  s.data['id'] = '0123456789abcdef0123456789abcdef';
  s.data['customerName'] = 'Jamie Tan';
  s.data['appointments'][0]['startAt'] = visitAt;
  s.data['appointments'][0]['fittingInvoiceId'] = 'fitting-fee';
  s.data['rentalPlan'] = {
    'pickupDate': '2026-10-23',
    'eventDate': '2026-10-24',
    'returnDate': '2026-10-25',
  };
  return s;
}

Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 1440,
  double scale = 1,
  double height = 1000,
}) async {
  viewport(t, Size(width, height));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      debugShowCheckedModeBanner: false,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: child,
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

Future<void> reveal(WidgetTester t, Finder f) async {
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('fitting-form-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await t.scrollUntilVisible(f, 200, scrollable: scroll);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'payment summary never labels pending, review or mismatched receipts as paid',
    (t) async {
      for (final change in [
        <String, dynamic>{'state': 'Pending'},
        {'reviewReason': 'Review required'},
        {'appointmentId': 'other'},
        {'amountCents': 100},
        {'invoiceNo': ''},
      ]) {
        final calls = <http.Request>[],
            api = mockApi(calls, feeChanges: change);
        addTearDown(api.close);
        await mount(t, FittingResultScreen(selection: customer(), api: api));
        expect(find.text('Fitting fee · RM 50.00 paid'), findsNothing);
        expect(
          find.text('Fitting fee · Review payment status'),
          findsOneWidget,
        );
        expect(calls.where((r) => r.method == 'POST'), isEmpty);
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'payment summary failure is explicit and does not fabricate a successful payment',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls, feeFailed: true);
      addTearDown(api.close);
      await mount(t, FittingResultScreen(selection: customer(), api: api));
      expect(
        find.textContaining('Fitting fee · Status unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Fitting fee · RM 50.00 paid'), findsNothing);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop uses customer context, one automatic real visit, visible decisions and a persistent save bar',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      await mount(t, FittingResultScreen(selection: customer(), api: api));
      expect(find.text('Jamie Tan'), findsOneWidget);
      expect(find.text('Plan reference · 89ABCDEF'), findsOneWidget);
      expect(find.text(planningTime(visitAt)), findsOneWidget);
      expect(find.text('Fitting fee · RM 50.00 paid'), findsOneWidget);
      expect(find.byKey(const ValueKey('fitting-visit')), findsNothing);
      expect(find.byType(FittingOptions), findsNWidgets(2));
      expect(find.text('Save fitting outcome').hitTestable(), findsOneWidget);
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      expect(find.text('Jamie Tan').hitTestable(), findsOneWidget);
      expect(find.text('Save fitting outcome').hitTestable(), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'adjustment instructions are visible while optional body measurements stay collapsed',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      await mount(t, FittingResultScreen(selection: customer(), api: api));
      await reveal(t, find.byKey(const ValueKey('fitting-option-Basic')));
      await tap(t, find.byKey(const ValueKey('fitting-option-Basic')));
      await reveal(t, find.byKey(const ValueKey('adjustment-gown')));
      expect(
        find.byKey(const ValueKey('adjustment-gown')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.textContaining('Required: describe the adjustment'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('body-bust')), findsNothing);
      await reveal(t, find.byKey(const ValueKey('fitting-body-measurements')));
      await tap(t, find.text('Body measurements'));
      await reveal(t, find.byKey(const ValueKey('body-bust')));
      expect(find.byKey(const ValueKey('body-bust')), findsOneWidget);
      expect(
        find.text('Next: Prepare the adjustment proposal'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'single visit auto-fill still requires a note and explicit actual attendance; exact visit is submitted',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      await mount(t, FittingResultScreen(selection: customer(), api: api));
      await tap(t, find.text('Save fitting outcome'));
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(
        find.textContaining('Select the visit, add a clear'),
        findsOneWidget,
      );
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended and chose to keep the ivory gown.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await tap(t, find.text('Save fitting outcome'));
      final post = calls.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body);
      expect(body['appointmentId'], 'appointment');
      expect(body['outcome'], 'Selected');
      expect(body['confirmed'], true);
      expect(body.containsKey('actualAt'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'multiple visits are not guessed; staff must explicitly choose the attended visit',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      final s = customer();
      (s.data['appointments'] as List).add({
        'id': 'second',
        'status': 'Confirmed',
        'type': 'Dress Trial',
        'startAt': visitAt + 86400000,
      });
      await mount(t, FittingResultScreen(selection: s, api: api));
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('fitting-visit')),
            )
            .initialValue,
        isNull,
      );
      await tap(t, find.byKey(const ValueKey('fitting-option-Considering')));
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended and is taking time to decide.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await tap(t, find.text('Save fitting outcome'));
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await t.drag(
        find.byKey(const ValueKey('fitting-form-scroll')),
        const Offset(0, 1500),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('fitting-visit')));
      await tap(t, find.text(planningTime(visitAt + 86400000)).last);
      await tap(t, find.text('Save fitting outcome'));
      expect(
        jsonDecode(
          calls.singleWhere((r) => r.method == 'POST').body,
        )['appointmentId'],
        'second',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'no eligible visit gives an explanation and exit instead of an empty dropdown',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      final s = customer();
      s.data['appointments'] = [];
      await mount(t, FittingResultScreen(selection: s, api: api));
      expect(find.text('No eligible fitting visit'), findsOneWidget);
      expect(find.text('Back to customer rental'), findsOneWidget);
      expect(find.byKey(const ValueKey('fitting-visit')), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'each decision previews a truthful next step without sending a mutation',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      await mount(t, FittingResultScreen(selection: customer(), api: api));
      for (final e in {
        'Reselect': 'Customer chooses another gown',
        'Considering': 'Await the customer’s decision',
        'NotProceeding': 'Close this fitting without a rental booking',
        'Selected': 'Prepare the proposal',
      }.entries) {
        await tap(t, find.byKey(ValueKey('fitting-option-${e.key}')));
        expect(find.text('Next: ${e.value}'), findsOneWidget);
      }
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop no-fitting review cannot manufacture an attended fitting or measurements',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      final s = customer();
      s.data['fittingChoice'] = {'mode': 'SkipFitting', 'accepted': true};
      await mount(t, FittingResultScreen(selection: s, api: api));
      expect(find.text('1. Customer decision'), findsNothing);
      expect(find.byType(FittingAssessmentEditor), findsNothing);
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Reviewed the gown, size and dates with the customer.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await tap(t, find.text('Approve no-fitting request'));
      final body = jsonDecode(
        calls.singleWhere((r) => r.method == 'POST').body,
      );
      expect(body['mode'], 'Waived');
      expect(body['appointmentId'], isNull);
      expect(body.containsKey('assessment'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'changing between compact and desktop layout keeps unsaved staff notes',
    (t) async {
      final calls = <http.Request>[], api = mockApi(calls);
      addTearDown(api.close);
      await mount(
        t,
        FittingResultScreen(selection: customer(), api: api),
        width: 390,
      );
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Keep this unsaved service note.',
      );
      t.view.physicalSize = const Size(1440, 1000);
      await t.pumpAndSettle();
      await reveal(t, find.byKey(const ValueKey('fitting-notes')));
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('fitting-notes')))
            .controller!
            .text,
        'Keep this unsaved service note.',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1000.0, 1440.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('workbench fits width $width and scale $scale', (t) async {
        final calls = <http.Request>[], api = mockApi(calls);
        addTearDown(api.close);
        await mount(
          t,
          FittingResultScreen(selection: customer(), api: api),
          width: width,
          scale: scale,
          height: 900,
        );
        await reveal(t, find.byKey(const ValueKey('fitting-notes')));
        expect(t.takeException(), isNull);
        if (scale < 1.7) {
          expect(
            find.text('Save fitting outcome').hitTestable(),
            findsOneWidget,
          );
        }
      });
    }
  }
  testWidgets('desktop staff workbench visual preview', (t) async {
    final calls = <http.Request>[], api = mockApi(calls);
    addTearDown(api.close);
    await mount(
      t,
      RepaintBoundary(
        key: const ValueKey('workbench-preview'),
        child: FittingResultScreen(selection: customer(), api: api),
      ),
      height: 1000,
    );
    await expectLater(
      find.byKey(const ValueKey('workbench-preview')),
      matchesGoldenFile('previews/fitting-workbench-2068.png'),
    );
    expect(t.takeException(), isNull);
  });
}
