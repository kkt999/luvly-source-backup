import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/rental_workspace.dart';
import 'package:luvly_app/packages/staff_rental_details.dart';
import 'package:luvly_app/payments/payment_api.dart';
import '../checkout_redesign_test.dart' show fonts, viewport;
import 'package_test.dart' show FakePackages;

String uid(String char) => List.filled(32, char).join();
Map<String, dynamic> invoice(String char, int amount, String state) => {
  'environment': 'sandbox',
  'id': uid(char),
  'title': 'Bridal Essentials',
  'appointmentId': 'visit',
  'amountCents': amount,
  'state': state,
  if (state == 'SandboxPaid') 'invoiceNo': 'PAY-2030-1042',
};
PackageSelection staffSelection({
  String char = 'a',
  String customer = 'Jane Lim',
  String stage = 'Locked',
  bool paid = false,
}) => PackageSelection({
  'id': uid(char),
  'name': 'Bridal Essentials',
  'customerName': customer,
  'totalCents': 84900,
  'services': [
    {
      'id': 'gown',
      'name': 'One wedding-gown rental',
      'description': '',
      'kind': 'Required',
      'priceCents': 0,
    },
  ],
  'selectedGowns': [
    {'name': 'Luna', 'size': 'M', 'colour': 'Ivory', 'dressId': 'gown1'},
  ],
  'selectedAccessories': [],
  'appointments': [],
  'paymentPolicyVersion': 1,
  'fittingWorkflowVersion': 1,
  'fittingDecision': {'state': 'Approved', 'mode': 'Attended'},
  'rentalPlan': {
    'pickupDate': '2030-10-23',
    'returnDate': '2030-10-25',
    'eventDate': '2030-10-24',
  },
  'promotion': {
    'code': 'ESSENTIAL50',
    'subtotalCents': 89900,
    'discountCents': 5000,
  },
  'invoice': invoice('b', 37450, stage == 'Held' ? 'Quoted' : 'SandboxPaid'),
  'balanceInvoice': invoice('c', 42450, paid ? 'SandboxPaid' : 'Quoted'),
  'rental': {
    'id': uid('e'),
    'state': stage,
    'policyVersion': 1,
    'pickupDate': '2030-10-23',
    'returnDate': '2030-10-25',
    'eventDate': '2030-10-24',
    'expiresAt': DateTime.utc(2030, 10, 23).millisecondsSinceEpoch,
    'depositCents': 37450,
    'depositTargetCents': 42450,
    'fittingCreditCents': 5000,
    'balanceCents': 42450,
    'securityCents': 30000,
    'paymentState': paid ? 'Paid' : 'DepositPaid',
    'securityState': paid ? 'Paid' : 'AwaitingPayment',
    'invoiceId': uid('b'),
    'balanceInvoiceId': uid('c'),
    'securityInvoiceId': uid('d'),
  },
});

Future<void> showWorkspace(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: portalTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  test(
    'stock reservation does not hide unpaid balance or security; credit is not subtracted twice',
    () {
      final view = StaffRentalView(staffSelection());
      expect(view.badge, 'Stock reserved');
      expect(
        view.paymentSummary,
        'RM 424.50 balance · due\nRM 300.00 security due',
      );
      expect(view.deposit.amount, 37450);
      expect(view.balance.amount, 42450);
      expect(view.nextStep, 'Collect balance & security');
      expect(view.readyForPickup, isFalse);
    },
  );
  test(
    'paid balances permit pickup guidance, but review or extension never does',
    () {
      final s = staffSelection(paid: true);
      expect(StaffRentalView(s).readyForPickup, isTrue);
      s.data['balanceInvoice']['reviewReason'] = 'Gateway review';
      expect(StaffRentalView(s).nextStep, 'Review payment status');
      expect(StaffRentalView(s).readyForPickup, isFalse);
      s.data['balanceInvoice'].remove('reviewReason');
      s.data['rental']['pendingExtension'] = {
        'expiresAt': DateTime.utc(2030, 10, 22).millisecondsSinceEpoch,
      };
      expect(StaffRentalView(s).readyForPickup, isFalse);
      expect(StaffRentalView(s).nextStep, 'Review date-change payment');
    },
  );
  test(
    'collected and returned records do not request fitting again or allow cancellation',
    () {
      final s = staffSelection(paid: true);
      s.data['rental'].addAll({'fulfilment': 'Collected', 'collectedAt': 1});
      expect(StaffRentalView(s).nextStep, 'Await return & inspection');
      expect(StaffRentalView(s).canCancel, isFalse);
      s.data['rental'].addAll({
        'fulfilment': 'Returned',
        'returnedAt': 2,
        'securityState': 'RefundDue',
        'refundDueCents': 27500,
      });
      expect(StaffRentalView(s).paymentSummary, 'RM 275.00 refund due');
      expect(StaffRentalView(s).nextStep, 'Arrange security refund');
    },
  );
  testWidgets(
    'details are not on list; closing the side panel preserves search',
    (tester) async {
      viewport(tester, const Size(1440, 1000));
      final api = FakePackages()
        ..rows.addAll([
          staffSelection(),
          staffSelection(char: 'f', customer: 'Amy Tan'),
        ]);
      await showWorkspace(
        tester,
        LivePackageScreen(api: api, staff: true, initialSelections: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('50% deposit'), findsNothing);
      expect(find.textContaining('Preferred gowns'), findsNothing);
      expect(find.text('Cancel rental'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Jane');
      await tester.pumpAndSettle();
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffRentalDetails), findsOneWidget);
      expect(tester.getSize(find.byType(StaffRentalDetails)).width, 660);
      expect(find.text('Rental dates'), findsOneWidget);
      expect(find.text('Payment summary'), findsOneWidget);
      await tester.tap(find.byTooltip('Close rental details'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Jane',
      );
      expect(find.text('Amy Tan'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancellation is under More and requires confirmation; refresh updates panel and list',
    (tester) async {
      viewport(tester, const Size(1440, 1000));
      final s = staffSelection();
      final calls = <http.Request>[];
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'fixture-token',
          client: MockClient((request) async {
            calls.add(request);
            if (request.method == 'POST') {
              expect(request.url.path, '/v1/rentals/${uid('e')}/cancel');
              s.data['rental']['state'] = 'Cancelled';
              return http.Response('{}', 200);
            }
            expect(request.url.path, '/v1/package-selections');
            return http.Response(
              jsonEncode({
                'selections': [s.data],
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      await showWorkspace(
        tester,
        LivePackageScreen(api: api, staff: true, initialSelections: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel rental'), findsNothing);
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel rental'), findsNothing);
      await tester.tap(find.byTooltip('More rental actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel rental'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.text('Keep rental'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.byTooltip('More rental actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel rental'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel rental'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST').length, 1);
      expect(find.byTooltip('More rental actions'), findsNothing);
      expect(find.text('Cancelled'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 660.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('rental list and details fit $width text $scale', (
        tester,
      ) async {
        viewport(tester, Size(width, 1000));
        final s = staffSelection();
        await showWorkspace(
          tester,
          StaffRentalWorkspace(selections: [s], onOpen: (_) {}),
          scale: scale,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final api = FakePackages()..rows.add(s);
        await showWorkspace(
          tester,
          StaffRentalDetails(
            selection: s,
            api: api,
            manager: false,
            onChanged: () {},
            onIssueInvoice: (_) async {},
          ),
          scale: scale,
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Gowns & accessories'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gowns & accessories'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final scene in ['list', 'details']) {
    testWidgets('staff rental visual $scene', (tester) async {
      viewport(tester, Size(scene == 'list' ? 1440 : 660, 1000));
      await tester.runAsync(fonts);
      final samples = [
        staffSelection(),
        staffSelection(char: 'f', customer: 'Mei Wong', stage: 'Held'),
        staffSelection(char: 'c', customer: 'Sarah Lee', paid: true),
        staffSelection(char: 'd', customer: 'Aina Tan', paid: true),
      ];
      samples[2].data['rental'].addAll({
        'fulfilment': 'Collected',
        'collectedAt': 1,
      });
      samples[3].data['rental'].addAll({
        'fulfilment': 'Returned',
        'collectedAt': 1,
        'returnedAt': 2,
        'securityState': 'RefundDue',
        'refundDueCents': 30000,
      });
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'fixture-token',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'selections': samples.map((s) => s.data).toList()}),
              200,
            ),
          ),
        ),
      );
      addTearDown(api.close);
      const key = ValueKey('rental-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: portalTheme,
            home: scene == 'list'
                ? Scaffold(
                    body: StaffRentalWorkspace(
                      selections: samples,
                      onOpen: (_) {},
                    ),
                  )
                : StaffRentalDetails(
                    selection: samples.first,
                    api: api,
                    manager: false,
                    onChanged: () {},
                    onIssueInvoice: (_) async {},
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scene == 'details') {
        expect(find.byTooltip('More rental actions'), findsOneWidget);
        expect(find.text('Cancel rental'), findsNothing);
        expect(find.text('Open rental workspace'), findsOneWidget);
      }
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('previews/staff-rental-$scene.png'),
      );
    });
  }
}
