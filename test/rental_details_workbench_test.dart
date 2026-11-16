import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/staff_rental_details.dart';
import 'package:luvly_app/packages/rental_handover_screen.dart';
import 'package:luvly_app/packages/fitting_result_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/payments/staff_payment_workspace.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/staff_rental_workspace_test.dart'
    show staffSelection, uid, invoice;

HttpPackageApi fixtureApi(
  List<http.Request> calls,
  PackageSelection selection, {
  bool fail = false,
  bool missing = false,
  Completer<http.Response>? pending,
}) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'staff-token',
    client: MockClient((r) async {
      calls.add(r);
      if (r.url.path == '/v1/package-selections') {
        if (pending != null) return pending.future;
        if (fail) return http.Response('{"error":"TRY_LATER"}', 503);
        return http.Response(
          jsonEncode({
            'selections': [
              staffSelection(char: 'f', customer: 'Other customer').data,
              if (!missing) selection.data,
            ],
          }),
          200,
        );
      }
      if (r.url.path == '/v1/invoices') {
        return http.Response(
          jsonEncode({
            'invoices': [
              {
                ...invoice('b', 37450, 'SandboxPaid'),
                'title': 'Booking deposit',
              },
              {...invoice('c', 42450, 'Quoted'), 'title': 'Remaining balance'},
              {...invoice('f', 99900, 'Quoted'), 'title': 'Unrelated invoice'},
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    }),
  ),
);
Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 1440,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: portalTheme,
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

StaffRentalDetails details(
  PackageSelection s,
  PackageApi api, {
  bool manager = false,
  bool workspace = true,
}) => StaffRentalDetails(
  selection: s,
  api: api,
  manager: manager,
  workspace: workspace,
  onChanged: () {},
  onIssueInvoice: (_) async {},
);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, int i) =>
    tap(t, find.byKey(ValueKey('rental-tab-$i')));
void main() {
  testWidgets(
    'quick drawer stays compact and opens the exact refreshed full workspace',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      await mount(t, details(s, api, workspace: false));
      expect(find.text('Rental dates'), findsOneWidget);
      expect(find.text('Payment summary'), findsOneWidget);
      expect(find.text('Update preparation'), findsNothing);
      await tap(t, find.text('Open rental workspace'));
      expect(find.text('Rental workspace'), findsOneWidget);
      expect(find.text('Jane Lim'), findsWidgets);
      expect(find.text('Other customer'), findsNothing);
      expect(find.byKey(const ValueKey('rental-tab-5')), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'all sections keep exact identity and use existing records without mutating them',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      s.data['fittingDecisionHistory'] = [
        {
          'outcome': 'Reselect',
          'recordedAt': 1792116000000,
          'note': 'Customer explored another gown.',
        },
      ];
      s.data['selectionHistory'] = [
        {
          'name': 'Earlier selection',
          'at': 1792116000000,
          'selectedGowns': [
            {'name': 'Original gown', 'size': 'S'},
          ],
          'totalCents': 89900,
        },
      ];
      await mount(t, details(s, api));
      for (var i = 0; i < 6; i++) {
        await tab(t, i);
        expect(find.text('Jane Lim').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      }
      expect(find.text('Customer explored another gown.'), findsOneWidget);
      expect(
        find.text('Previous selection · Earlier selection'),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  for (final missing in [false, true]) {
    testWidgets(
      'failed or deleted record missing=$missing blocks every mutation and never substitutes a different customer',
      (t) async {
        final calls = <http.Request>[],
            s = staffSelection(),
            api = fixtureApi(calls, s, fail: !missing, missing: missing);
        addTearDown(api.close);
        await mount(t, details(s, api));
        expect(find.text('Other customer'), findsNothing);
        expect(find.text('Refresh record'), findsOneWidget);
        final more = t.widget<PopupMenuButton<String>>(
          find.byType(PopupMenuButton<String>),
        );
        expect(more.enabled, false);
        await tab(t, 1);
        expect(find.text('Update preparation'), findsNothing);
        await tab(t, 3);
        final handover = t.widget<FilledButton>(
          find
              .byWidgetPredicate(
                (w) => w is FilledButton && w.child is! SizedBox,
              )
              .first,
        );
        expect(handover.onPressed, isNull);
        expect(calls.where((r) => r.method == 'POST'), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'workspace actions remain blocked while the authoritative refresh is pending',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          pending = Completer<http.Response>(),
          api = fixtureApi(calls, s, pending: pending);
      addTearDown(api.close);
      viewport(t, const Size(1440, 1000));
      await t.pumpWidget(
        MaterialApp(theme: portalTheme, home: details(s, api)),
      );
      await t.pump();
      expect(
        t
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        false,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      pending.complete(
        http.Response(
          jsonEncode({
            'selections': [s.data],
          }),
          200,
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        true,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'payment links open only that invoice and staff can explicitly return to all payments',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      await mount(t, details(s, api));
      await tab(t, 2);
      await tap(t, find.text('View remaining balance'));
      final page = t.widget<LivePaymentsScreen>(
        find.byType(LivePaymentsScreen),
      );
      expect(page.staff, true);
      expect(page.focusInitialInvoice, true);
      expect(page.initialInvoiceId, uid('c'));
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      expect(
        t
            .widget<CheckoutInvoiceCard>(find.byType(CheckoutInvoiceCard))
            .invoice
            .id,
        uid('c'),
      );
      expect(find.text('Unrelated invoice'), findsNothing);
      await tap(t, find.text('View all payments & receipts'));
      expect(find.byType(CheckoutInvoiceCard), findsNothing);
      expect(
        t
            .widget<StaffPaymentWorkspace>(find.byType(StaffPaymentWorkspace))
            .invoices,
        hasLength(3),
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'pickup navigation opens existing checklist without marking collection',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(paid: true),
          api = fixtureApi(calls, s);
      s.data['rental']['gowns'] = s.selectedGowns;
      addTearDown(api.close);
      await mount(t, details(s, api, manager: false));
      await tab(t, 3);
      await tap(t, find.text('Open pickup checklist'));
      final page = t.widget<RentalHandoverScreen>(
        find.byType(RentalHandoverScreen),
      );
      expect(page.manager, false);
      expect(page.rental['id'], uid('e'));
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(s.data['rental']['collectedAt'], isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'fitting actions open the existing exact plan without creating attendance or another appointment',
    (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      s.data.remove('rental');
      s.data.remove('invoice');
      s.data.remove('balanceInvoice');
      s.data['fittingDecision'] = null;
      s.data['fittingWorkflowVersion'] = 2;
      s.data['appointments'] = [
        {
          'id': 'visit',
          'type': 'Dress Trial',
          'status': 'Confirmed',
          'startAt': 1792648800000,
        },
      ];
      await mount(t, details(s, api));
      await tab(t, 1);
      await tap(t, find.text('Record fitting outcome'));
      expect(
        t
            .widget<FittingResultScreen>(find.byType(FittingResultScreen))
            .selection
            .id,
        s.id,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  for (final stage in ['Held', 'Cancelled', 'Expired', 'PaymentReview']) {
    testWidgets('no handover shortcut for rental stage $stage', (t) async {
      final calls = <http.Request>[],
          s = staffSelection(stage: stage),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      await mount(t, details(s, api));
      await tab(t, 3);
      expect(find.text('Open pickup checklist'), findsNothing);
      expect(
        find.textContaining('A confirmed rental is required'),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    });
  }
  for (final stage in ['Collected', 'Returned']) {
    testWidgets('handover label follows saved fulfilment $stage', (t) async {
      final calls = <http.Request>[],
          s = staffSelection(paid: true),
          api = fixtureApi(calls, s);
      s.data['rental']['fulfilment'] = stage;
      s.data['rental']['collectedAt'] = 1792116000000;
      if (stage == 'Returned') {
        s.data['rental']['returnedAt'] = 1792119600000;
      }
      addTearDown(api.close);
      await mount(t, details(s, api, manager: true));
      await tab(t, 3);
      expect(find.text('Open pickup checklist'), findsNothing);
      expect(
        find.text(
          stage == 'Collected'
              ? 'Open return inspection'
              : 'Review inspection & security',
        ),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    });
  }
  for (final width in [320.0, 660.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full rental workspace fits $width at $scale', (t) async {
        final calls = <http.Request>[],
            s = staffSelection(),
            api = fixtureApi(calls, s);
        addTearDown(api.close);
        await mount(t, details(s, api), width: width, scale: scale);
        for (final i in [1, 2, 3, 4, 5]) {
          await tab(t, i);
          expect(t.takeException(), isNull);
        }
      });
    }
  }
  for (final selected in [0, 2]) {
    testWidgets('rental workbench visual tab $selected', (t) async {
      final calls = <http.Request>[],
          s = staffSelection(),
          api = fixtureApi(calls, s);
      addTearDown(api.close);
      await mount(
        t,
        RepaintBoundary(
          key: const ValueKey('rental-workbench-preview'),
          child: details(s, api),
        ),
      );
      await tab(t, selected);
      await expectLater(
        find.byKey(const ValueKey('rental-workbench-preview')),
        matchesGoldenFile('previews/rental-workbench-2069-$selected.png'),
      );
      expect(t.takeException(), isNull);
    });
  }
}
