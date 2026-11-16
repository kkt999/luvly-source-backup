import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/customer_package_card.dart';
import 'package:luvly_app/packages/customer_package_details.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/bookings/booking_screens.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_test.dart' show FakePackages;
import 'packages/package_gowns_test.dart' show gownPackage;

final clock = DateTime.utc(2026, 10, 20, 12);
PackageSelection plan() => PackageSelection({
  'id': 'plan-a',
  'name': 'Bridal Essentials',
  'packageId': 'essential',
  'customerName': 'Customer',
  'totalCents': 89900,
  'services': [
    {
      'id': 'gown',
      'name': 'One wedding-gown rental',
      'description': 'Your selected gown',
      'kind': 'Required',
      'priceCents': 0,
    },
  ],
  'selectedGowns': [
    {
      'dressId': 'isabelle',
      'name': 'Isabelle gown',
      'size': 'XS',
      'colour': 'Ivory',
    },
  ],
  'selectedAccessories': [],
  'appointments': [],
  'rentalPlan': {
    'eventDate': '2026-10-23',
    'pickupDate': '2026-10-22',
    'returnDate': '2026-10-24',
  },
});
Map<String, dynamic> invoice(String id, {String state = 'Quoted'}) => {
  'id': id == 'deposit-a' ? 'a' * 32 : 'b' * 32,
  'title': 'Package payment',
  'appointmentId': 'visit',
  'amountCents': 44950,
  'state': state,
  'environment': 'sandbox',
  if (state == 'SandboxPaid') 'invoiceNo': 'TP-RECEIPT',
};
PackageSelection reserved() {
  final s = plan();
  s.data['rental'] = {
    'id': 'rental-a',
    'state': 'Locked',
    'paymentState': 'DepositPaid',
    'depositCents': 44950,
    'balanceCents': 44950,
    'securityCents': 30000,
    'securityState': 'AwaitingPayment',
    'balanceInvoiceId': 'balance-a',
    'securityInvoiceId': 'security-a',
    ...s.data['rentalPlan'] as Map,
  };
  s.data['invoice'] = invoice('deposit-a', state: 'SandboxPaid');
  s.data['balanceInvoice'] = invoice('balance-a');
  return s;
}

CustomerPackageStep step(PackageSelection s) =>
    customerPackageStep(s, now: clock);

class _ReadPackages extends FakePackages {
  Future<void>? wait;
  bool readError = false;
  int reads = 0;

  @override
  Future<List<PackageSelection>> selections() async {
    reads++;
    await wait;
    if (readError) throw StateError('internal transport failure');
    return super.selections();
  }
}

Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double scale = 1,
  bool settle = true,
}) async {
  viewport(t, Size(width, 1000));
  await fonts();
  final model = AppModel()
    ..accountId = 'bride'
    ..name = 'Customer';
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
        home: RepaintBoundary(key: const ValueKey('capture'), child: child),
      ),
    ),
  );
  if (settle) await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(finder.first);
  await t.pumpAndSettle();
  await t.tap(finder.first);
  await t.pumpAndSettle();
}

void main() {
  test(
    'unbooked plan has exactly the fitting step, not separate booking and options actions',
    () {
      expect(step(plan()).label, 'Arrange fitting');
      expect(step(plan()).action, CustomerPackageAction.fitting);
      final s = plan()..data.remove('rentalPlan');
      expect(step(s).label, 'Complete your plan');
    },
  );
  test(
    'active appointments never offer another initial fitting and pending fees target the exact invoice',
    () {
      for (final status in ['Confirmed', 'Requested', 'AwaitingPayment']) {
        final s = plan();
        s.data['appointments'] = [
          {
            'id': 'visit-a',
            'status': status,
            'startAt': clock
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch,
            'fittingInvoiceId': 'fitting-a',
            'paymentExpiresAt': clock
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
          },
        ];
        final next = step(s);
        expect(
          next.action,
          status == 'AwaitingPayment'
              ? CustomerPackageAction.payment
              : CustomerPackageAction.appointment,
        );
        expect(
          next.targetId,
          status == 'AwaitingPayment' ? 'fitting-a' : 'visit-a',
        );
      }
    },
  );
  test(
    'expired or missing fitting payment records never offer pay now or another fitting',
    () {
      for (final patch in [
        {'paymentExpiresAt': clock.millisecondsSinceEpoch},
        {'fittingInvoiceId': null},
      ]) {
        final s = plan();
        s.data['appointments'] = [
          {'status': 'AwaitingPayment', 'fittingInvoiceId': 'fee-a', ...patch},
        ];
        expect(step(s).action, CustomerPackageAction.details);
      }
    },
  );
  test(
    'completed visits, no fitting, team review and accepted decisions do not ask to book again',
    () {
      final s = plan();
      s.data['appointments'] = [
        {'status': 'Completed'},
      ];
      expect(step(s).action, CustomerPackageAction.details);
      s.data['appointments'] = [];
      s.data['fittingChoice'] = {'mode': 'SkipFitting'};
      expect(step(s).status, 'No-fitting request sent');
      for (final state in [
        'QuoteNeeded',
        'AwaitingReview',
        'Approved',
        'Considering',
        'Declined',
      ]) {
        s.data['fittingDecision'] = {'state': state};
        expect(step(s).action, CustomerPackageAction.details);
      }
      s.data['fittingQuote'] = {'state': 'AwaitingCustomer'};
      expect(step(s).action, CustomerPackageAction.proposal);
      s.data['fittingQuote'] = {'state': 'Outdated'};
      expect(step(s).status, 'Updated proposal needed');
      s.data.remove('fittingQuote');
      s.data['fittingDecision'] = {'state': 'Reselect'};
      expect(step(s).action, CustomerPackageAction.proposal);
    },
  );
  test(
    'deposit, balance, security and verification states select the relevant payment only',
    () {
      final s = reserved();
      expect(step(s).label, 'Pay remaining balance');
      expect(step(s).targetId, 'balance-a');
      s.data['balanceInvoice'] = invoice('balance-a', state: 'Pending');
      expect(step(s).label, 'Check balance payment');
      s.data['balanceInvoice'] = invoice('balance-a', state: 'SandboxPaid');
      expect(step(s).label, 'Pay security deposit');
      expect(step(s).targetId, 'security-a');
      s.data['rental']['securityState'] = 'Paid';
      s.data['rental']['paymentState'] = 'Paid';
      expect(step(s).action, CustomerPackageAction.details);
      s.data['rental']['state'] = 'Held';
      s.data['rental']['expiresAt'] = clock
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch;
      s.data['invoice'] = invoice('deposit-a');
      expect(step(s).label, 'Pay booking deposit');
      expect(step(s).targetId, 'a' * 32);
      s.data['rental']['expiresAt'] = clock.millisecondsSinceEpoch;
      expect(step(s).status, 'Reservation hold ended');
    },
  );
  test(
    'missing payment targets, review and closed histories cannot lead to new pay or fitting actions',
    () {
      final s = reserved();
      s.data['rental'].remove('balanceInvoiceId');
      expect(step(s).action, CustomerPackageAction.details);
      s.data['rental']['state'] = 'PaymentReview';
      expect(step(s).label, 'Check payment status');
      s.data['rental']['state'] = 'Cancelled';
      expect(step(s).action, CustomerPackageAction.details);
      s.data['rental']['state'] = 'Expired';
      expect(step(s).action, CustomerPackageAction.details);
    },
  );
  test(
    'required final fitting routes to an included fitting or exact active visit, never initial rental setup',
    () {
      final s = reserved();
      s.data['balanceInvoice'] = invoice('balance-a', state: 'SandboxPaid');
      s.data['rental']['securityState'] = 'Paid';
      s.data['rental']['paymentState'] = 'Paid';
      s.data['rental']['fittingQuote'] = {
        'adjustmentPlan': {'followUp': 'Required'},
      };
      expect(step(s).action, CustomerPackageAction.includedFitting);
      s.data['appointments'] = [
        {'id': 'final-a', 'status': 'Confirmed'},
      ];
      expect(step(s).targetId, 'final-a');
      s.data['rental']['finalFitting'] = {'state': 'Completed'};
      expect(step(s).status, 'Reserved');
    },
  );
  test(
    'collection, return issues, actual return and refund state remain customer-readable',
    () {
      final s = reserved();
      s.data['rental']['fulfilment'] = 'Collected';
      expect(step(s).status, 'Collected');
      s.data['rental']['returnIssue'] = {'state': 'Open'};
      expect(step(s).status, 'Return needs review');
      s.data['rental']['fulfilment'] = 'Returned';
      s.data['rental']['securityState'] = 'RefundDue';
      expect(step(s).status, 'Returned');
      expect(step(s).description, contains('refund'));
      expect(step(s).action, CustomerPackageAction.details);
    },
  );
  testWidgets(
    'list is compact: one main action, details link, no promo, service list or secondary CRUD buttons',
    (t) async {
      final api = FakePackages()..rows.add(plan());
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      expect(find.widgetWithText(AppBar, 'My packages'), findsOneWidget);
      expect(find.text('Arrange fitting'), findsOneWidget);
      expect(find.text('View package details'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      for (final hidden in [
        'Book an appointment',
        'Fitting options',
        'Change rental dates',
        'Add promo code',
        'One wedding-gown rental',
      ]) {
        expect(find.text(hidden), findsNothing);
      }
      expect(find.text('Isabelle gown · XS'), findsOneWidget);
      expect(find.text('Rental · Not reserved'), findsOneWidget);
      expect(find.text('22–24 Oct 2026'), findsOneWidget);
      expect(find.text('23 Oct 2026'), findsOneWidget);
      expect(find.text('RM 899.00'), findsOneWidget);
      expect(find.text('Upcoming fitting'), findsNothing);
    },
  );
  testWidgets(
    'a real upcoming fitting is separate from rental confirmation and links to the same visit',
    (t) async {
      final now = DateTime.now().toUtc();
      final first = now.add(const Duration(days: 2)).millisecondsSinceEpoch;
      final s = plan()
        ..data['appointments'] = [
          {
            'id': 'past',
            'status': 'Confirmed',
            'type': 'Dress Trial',
            'startAt': now
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
          },
          {
            'id': 'later',
            'status': 'Confirmed',
            'type': 'Dress Trial',
            'startAt': now.add(const Duration(days: 4)).millisecondsSinceEpoch,
          },
          {
            'id': 'upcoming',
            'status': 'Confirmed',
            'type': 'Dress Trial',
            'scheduledStartAt': first,
            'startAt': first,
          },
        ];
      final api = FakePackages()..rows.add(s);
      final original = jsonEncode(s.data);
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      expect(find.text('Fitting booked'), findsOneWidget);
      expect(find.text('Rental · Not reserved'), findsOneWidget);
      expect(find.text('Upcoming fitting'), findsOneWidget);
      expect(find.text(paymentDateLabel(first)), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'View appointment'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'View package details'),
        findsOneWidget,
      );
      await tap(t, 'View appointment');
      expect(
        t
            .widget<LiveAppointments>(find.byType(LiveAppointments))
            .initialAppointmentId,
        'upcoming',
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, 'View package details');
      expect(
        t
            .widget<CustomerPackageDetails>(find.byType(CustomerPackageDetails))
            .selection
            .id,
        s.id,
      );
      expect(jsonEncode(s.data), original);
      expect(api.selectionsSaved + api.invoicesIssued, 0);
    },
  );
  testWidgets(
    'a past confirmed fitting stays confirmed and a reserved rental shows its locked dates',
    (t) async {
      final s = reserved();
      final stamp = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      s.data['appointments'] = [
        {
          'id': 'past',
          'type': 'Dress Trial',
          'status': 'Confirmed',
          'scheduledStartAt': stamp,
        },
      ];
      s.data['rental'].addAll({
        'pickupDate': '2026-12-31',
        'returnDate': '2027-01-02',
        'eventDate': '2027-01-01',
      });
      s.data['selectedGowns'].add({'name': 'Cathedral gown'});
      s.data['agreedTotalCents'] = 99950;
      final api = FakePackages()..rows.add(s);
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      expect(find.text('2 gowns selected'), findsOneWidget);
      expect(find.text('Rental · Reserved'), findsOneWidget);
      expect(find.text('1 Jan 2027'), findsOneWidget);
      expect(find.text('31 Dec 2026 – 2 Jan 2027'), findsOneWidget);
      expect(find.text('Confirmed fitting · awaiting update'), findsOneWidget);
      expect(find.text(paymentDateLabel(stamp)), findsOneWidget);
      expect(find.text('Upcoming fitting'), findsNothing);
      expect(find.text('Completed fitting'), findsNothing);
      expect(find.text('RM 999.50'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Pay remaining balance'),
        findsOneWidget,
      );
      await tap(t, 'View package details');
      expect(find.text('Isabelle gown · XS'), findsOneWidget);
      expect(find.text('Cathedral gown'), findsOneWidget);
    },
  );
  testWidgets(
    'completed fitting uses recorded attendance and directs the customer to the proposal',
    (t) async {
      final s = plan();
      final attended = DateTime.utc(2026, 10, 18, 7).millisecondsSinceEpoch;
      s.data['appointments'] = [
        {
          'id': 'attended',
          'status': 'Completed',
          'type': 'Dress Trial',
          'scheduledStartAt': DateTime.utc(
            2026,
            10,
            18,
            6,
          ).millisecondsSinceEpoch,
          'actualAttendedAt': attended,
        },
      ];
      s.data['fittingQuote'] = {'state': 'AwaitingCustomer'};
      s.data['fittingDecision'] = {
        'appointmentId': 'attended',
        'state': 'QuoteNeeded',
      };
      final api = FakePackages()..rows.add(s);
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      expect(find.text('Completed fitting'), findsOneWidget);
      expect(find.text(paymentDateLabel(attended)), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Review fitting proposal'),
        findsOneWidget,
      );
      expect(find.text('View appointment'), findsNothing);
      expect(find.text('Rental · Not reserved'), findsOneWidget);
    },
  );
  testWidgets(
    'only an active fitting invoice leads to the existing payment screen',
    (t) async {
      final now = DateTime.now();
      final s = plan()
        ..data['appointments'] = [
          {
            'id': 'pending',
            'type': 'Dress Trial',
            'status': 'AwaitingPayment',
            'startAt': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
            'paymentExpiresAt': now
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
            'fittingInvoiceId': 'actual-fee-invoice',
          },
        ];
      final api = FakePackages()..rows.add(s);
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      expect(find.text('Fitting awaiting payment'), findsOneWidget);
      await tap(t, 'Pay fitting fee');
      expect(
        t
            .widget<LivePaymentsScreen>(find.byType(LivePaymentsScreen))
            .initialInvoiceId,
        'actual-fee-invoice',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'loading, retry and the empty action use the original packages destination',
    (t) async {
      final pending = Completer<void>();
      final api = _ReadPackages()
        ..wait = pending.future
        ..readError = true;
      await mount(
        t,
        LivePackageScreen(api: api, initialSelections: true),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No packages selected yet'), findsNothing);
      pending.complete();
      await t.pumpAndSettle();
      expect(
        find.text('Could not load your packages. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('internal transport'), findsNothing);
      api.readError = false;
      await tap(t, 'Retry');
      expect(find.text('No packages selected yet'), findsOneWidget);
      await tap(t, 'Browse packages');
      expect(find.widgetWithText(AppBar, 'Service packages'), findsOneWidget);
      await tap(t, 'My packages');
      expect(find.text('No packages selected yet'), findsOneWidget);
      expect(api.reads, 2);
    },
  );
  testWidgets(
    'focused scope, search, rental filter and refresh keep their own state',
    (t) async {
      final first = plan();
      final second = PackageSelection({
        ...reserved().data,
        'id': 'another-plan',
        'name': 'Another saved selection',
        'selectedGowns': [
          {'name': 'Amelia gown', 'size': 'L'},
        ],
      });
      final api = _ReadPackages()..rows.addAll([first, second]);
      await mount(
        t,
        LivePackageScreen(
          api: api,
          initialSelections: true,
          initialSelectionId: first.id,
        ),
      );
      expect(find.text('Showing your selected plan'), findsOneWidget);
      expect(find.text('Another saved selection'), findsNothing);
      final field = find.byType(TextField);
      await t.enterText(field, 'Amelia 24 Oct');
      await t.pumpAndSettle();
      expect(find.text('No matching packages'), findsOneWidget);
      await tap(t, 'Show all selections');
      expect(find.text('Another saved selection'), findsOneWidget);
      await t.tap(find.byTooltip('Rental status: All packages'));
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(const ValueKey('list-option-Rental status-Reserved')),
      );
      await t.pumpAndSettle();
      expect(find.text('Rental status · Reserved'), findsOneWidget);
      expect(find.text('Another saved selection'), findsOneWidget);
      final pending = Completer<void>();
      api.wait = pending.future;
      await t.tap(find.byTooltip('Refresh packages'));
      await t.pump();
      expect(find.text('Another saved selection'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, 'Amelia 24 Oct');
      expect(find.text('Rental status · Reserved'), findsOneWidget);
      await t.tap(find.byTooltip('Clear search'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('Another saved selection'), findsOneWidget);
      expect(api.reads, 2);
    },
  );
  testWidgets(
    'details preserve included services and date edits while refresh keeps the same selection',
    (t) async {
      final s = plan(), calls = <http.Request>[];
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'token',
          client: MockClient((r) async {
            calls.add(r);
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
      await mount(
        t,
        CustomerPackageDetails(
          selection: s,
          api: api,
          onChanged: () {},
          onContinue: (_, _) async {},
        ),
      );
      expect(find.text('Change dates'), findsOneWidget);
      await tap(t, 'What is included');
      expect(find.text('One wedding-gown rental'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), true);
      await t.scrollUntilVisible(
        find.text('Change dates'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await tap(t, 'Change dates');
      expect(find.byType(PackageRentalScreen), findsOneWidget);
      expect(
        t
            .widget<PackageRentalScreen>(find.byType(PackageRentalScreen))
            .selection
            .id,
        'plan-a',
      );
      expect(
        t
            .widget<PackageRentalScreen>(find.byType(PackageRentalScreen))
            .editDates,
        true,
      );
    },
  );
  testWidgets(
    'stale list arrange action rechecks the same record and opens the newly booked visit instead',
    (t) async {
      final s = plan();
      var booked = false;
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'token',
          client: MockClient((r) async {
            if (r.url.path == '/v1/packages') {
              return http.Response(
                jsonEncode({
                  'packages': [gownPackage().toJson()],
                }),
                200,
              );
            }
            final fresh = {
              ...s.data,
              'appointments': booked
                  ? [
                      {
                        'id': 'visit-new',
                        'status': 'Confirmed',
                        'startAt': DateTime.now()
                            .add(const Duration(days: 1))
                            .millisecondsSinceEpoch,
                      },
                    ]
                  : [],
            };
            return http.Response(
              jsonEncode({
                'selections': [fresh],
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      await mount(t, LivePackageScreen(api: api, initialSelections: true));
      booked = true;
      await tap(t, 'Arrange fitting');
      expect(find.byType(PackageRentalScreen), findsNothing);
      expect(find.byType(LiveAppointments), findsOneWidget);
      expect(
        t
            .widget<LiveAppointments>(find.byType(LiveAppointments))
            .initialAppointmentId,
        'visit-new',
      );
    },
  );
  testWidgets(
    'details refresh failure disables mutations instead of acting on another or stale plan',
    (t) async {
      final api = FakePackages();
      await mount(
        t,
        CustomerPackageDetails(
          selection: plan(),
          api: api,
          onChanged: () {},
          onContinue: (_, _) async {},
        ),
      );
      expect(
        find.textContaining('This package could not be reloaded'),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Arrange fitting'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('compact card fits $width at large text', (t) async {
      final s = plan()
        ..data['name'] =
            'The Bridal Celebration Package With a Cathedral Gown and a Second Reception Look';
      final api = FakePackages()..rows.add(s);
      await mount(
        t,
        LivePackageScreen(api: api, initialSelections: true),
        width: width,
        scale: 2,
      );
      await t.drag(find.byType(ListView).first, const Offset(0, -500));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('compact my packages preview', (t) async {
    final s = plan()
      ..data['rentalPlan'] = {
        'pickupDate': '2031-11-27',
        'eventDate': '2031-11-28',
        'returnDate': '2031-11-29',
      }
      ..data['appointments'] = [
        {
          'id': 'fitting',
          'type': 'Dress Trial',
          'status': 'Confirmed',
          'startAt': DateTime.utc(2031, 11, 21, 6).millisecondsSinceEpoch,
        },
      ];
    final api = FakePackages()..rows.add(s);
    await mount(t, LivePackageScreen(api: api, initialSelections: true));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('previews/my-packages-2066.png'),
    );
  });
}
