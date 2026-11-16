import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/final_fitting_panel.dart';
import 'package:luvly_app/packages/fitting_proposal_screen.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/rental_handover_screen.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_review_dialog.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'fitting_proposal_test.dart' show mount, tap;
import 'packages/package_rental_test.dart' show selection;
import 'packages/package_gowns_test.dart' show gownPackage;
import 'fitting_proposal_test.dart' show proposed;

PackageSelection finalSelection() {
  final s = selection();
  s.data.addAll({
    'rentalId': 'b' * 32,
    'rental': {
      'id': 'b' * 32,
      'state': 'Locked',
      'appointmentId': 'initial',
      'fittingQuote': {
        'adjustmentPlan': {'followUp': 'Required'},
      },
    },
    'serviceProgress': {
      'rentalId': 'b' * 32,
      'revision': 2,
      'alterationVersion': 1,
      'alteration': 'Completed',
    },
    'appointments': [
      {
        'id': 'initial',
        'type': 'Dress Trial',
        'status': 'Completed',
        'startAt': 1792116000000,
      },
      {
        'id': 'follow-up',
        'type': 'Dress Trial',
        'status': 'Confirmed',
        'feeIncluded': true,
        'startAt': 1792116000000,
      },
    ],
  });
  return s;
}

HttpPaymentApi transport(List<http.Request> calls, {bool fail = false}) =>
    HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'unit-test',
      client: MockClient((r) async {
        calls.add(r);
        return http.Response(
          jsonEncode(
            fail ? {'error': 'FINAL_FITTING_PENDING'} : {'saved': true},
          ),
          fail ? 409 : 200,
        );
      }),
    );

void main() {
  testWidgets(
    'reported return issue uses its own confirmation and does not submit a return or deduction',
    (t) async {
      final calls = <http.Request>[];
      final rental = <String, dynamic>{
        'id': 'b' * 32,
        'state': 'Locked',
        'collectedAt': 1792116000000,
        'gowns': <dynamic>[],
        'accessories': <dynamic>[],
        'pickupDate': '2026-10-20',
        'returnDate': '2026-10-22',
        'balanceCents': 44950,
        'securityCents': 30000,
        'paymentState': 'Paid',
        'securityState': 'Paid',
      };
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'unit-test',
        client: MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode({
              ...rental,
              'returnIssue': {
                'state': 'Open',
                'note': 'Missing veil needs customer and manager review.',
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await mount(t, const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          home: RentalHandoverScreen(rental: rental, api: api),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextField).at(2),
        'Missing veil needs customer and manager review.',
      );
      await tap(t, find.text('Record return issue for review'));
      expect(find.text('Record a return issue?'), findsOneWidget);
      expect(calls, isEmpty);
      await tap(t, find.text('Confirm'));
      expect(jsonDecode(calls.single.body), {
        'action': 'report-return-issue',
        'reason': 'Missing veil needs customer and manager review.',
      });
      expect(
        find.textContaining('Return issue awaiting review'),
        findsOneWidget,
      );
      expect(find.text('Return inspection'), findsOneWidget);
    },
  );
  testWidgets(
    'changing package opens the new package on the same plan without keeping ineligible old selections',
    (t) async {
      final calls = <http.Request>[];
      final p = gownPackage();
      final newer = {
        ...p.toJson(),
        'id': 'new-package',
        'name': 'Signature Bridal',
      };
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'unit-test',
          client: MockClient((r) async {
            calls.add(r);
            return http.Response(
              jsonEncode(
                r.url.path == '/v1/packages'
                    ? {
                        'packages': [newer],
                      }
                    : {'dresses': []},
              ),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      final s = proposed();
      s.data['packageId'] = 'old-package';
      await mount(
        t,
        FittingProposalPanel(
          selection: s,
          api: api,
          staff: false,
          manager: false,
          reload: () {},
        ),
      );
      await tap(t, find.text('Change package'));
      await tap(t, find.textContaining('Signature Bridal'));
      expect(find.byType(PackageChoiceScreen), findsOneWidget);
      final screen = t.widget<PackageChoiceScreen>(
        find.byType(PackageChoiceScreen),
      );
      expect(screen.package.id, 'new-package');
      expect(identical(screen.revising, s), true);
      final posts = calls.where((r) => r.method == 'POST').toList();
      expect(posts.map((r) => r.url.path), ['/v1/package-availability']);
      expect(jsonDecode(posts.single.body)['packageId'], 'new-package');
    },
  );
  test('non-attendance is staff-only, distinct from completion', () {
    expect(canMoveBooking('Confirmed', 'NoShow', staff: true), true);
    expect(canMoveBooking('Confirmed', 'NoShow', staff: false), false);
    expect(canMoveBooking('Completed', 'NoShow', staff: true), false);
    expect(bookingStatusLabel('NoShow'), 'Did not attend');
  });
  testWidgets(
    'final fitting requires linked visit, meaningful note and actual attendance confirmation',
    (t) async {
      final calls = <http.Request>[];
      final live = HttpPackageApi(transport: transport(calls));
      addTearDown(live.close);
      var saved = 0;
      await mount(
        t,
        FinalFittingPanel(
          selection: finalSelection(),
          api: live,
          onSaved: () => saved++,
        ),
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record final fitting'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.byType(DropdownButtonFormField<String>));
      await tap(t, find.textContaining('MYT').last);
      await t.enterText(
        find.byType(TextField),
        'Customer checked the waist adjustment and accepted the fit.',
      );
      await tap(t, find.byType(CheckboxListTile));
      await tap(t, find.text('Record final fitting'));
      expect(saved, 1);
      expect(calls.length, 1);
      final body = jsonDecode(calls.single.body);
      expect(calls.single.url.path, endsWith('/final-fitting'));
      expect(body['appointmentId'], 'follow-up');
      expect(body['confirmed'], true);
      expect(body.keys.toSet(), {
        'requestId',
        'rentalId',
        'appointmentId',
        'confirmed',
        'note',
      });
    },
  );
  testWidgets(
    'unfinished alterations and missing follow-up do not offer a completion bypass',
    (t) async {
      final api = HttpPackageApi(transport: transport([]));
      addTearDown(api.close);
      final s = finalSelection();
      s.data['serviceProgress']['alteration'] = 'InProgress';
      s.data['appointments'] = [];
      await mount(t, FinalFittingPanel(selection: s, api: api, onSaved: () {}));
      expect(find.textContaining('book a linked Dress Trial'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record final fitting'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'refund review validates evidence and records an explicit bounded outcome',
    (t) async {
      final calls = <http.Request>[], api = transport(calls);
      addTearDown(api.close);
      const invoice = SandboxInvoice(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        title: 'Fitting fee',
        appointmentId: 'visit',
        amountCents: 5000,
        state: 'SandboxPaid',
        canResolveReview: true,
      );
      await mount(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPaymentReview(context, invoice, api),
            child: const Text('Review'),
          ),
        ),
      );
      await tap(t, find.text('Review'));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save reviewed outcome'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField).at(0), '25.00');
      await t.enterText(
        find.byType(TextField).at(1),
        'Approved partial refund after reviewing cancellation terms.',
      );
      await tap(t, find.byType(CheckboxListTile));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save reviewed outcome'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField).at(2), 'REF-verified-001');
      await tap(t, find.text('Save reviewed outcome'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(jsonDecode(calls.single.body)['refundCents'], 2500);
      expect(calls.single.url.path, endsWith('/resolve-review'));
    },
  );
  testWidgets(
    'resolved refunds retain receipt but are not shown as a new payment success',
    (t) async {
      const i = SandboxInvoice(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        title: 'Fitting fee',
        appointmentId: 'visit',
        amountCents: 5000,
        state: 'SandboxPaid',
        reviewResolution: {'state': 'RefundRecorded', 'refundCents': 5000},
      );
      await mount(
        t,
        const CheckoutInvoiceCard(
          invoice: i,
          staff: false,
          busy: false,
          focused: true,
        ),
      );
      expect(find.text('Payment successful'), findsNothing);
      expect(find.text('Refund recorded'), findsOneWidget);
      expect(find.text('View receipt'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('final fitting layout $width at large text', (t) async {
      final api = HttpPackageApi(transport: transport([]));
      addTearDown(api.close);
      await mount(
        t,
        RepaintBoundary(
          key: const Key('final-fitting-preview'),
          child: FinalFittingPanel(
            selection: finalSelection(),
            api: api,
            onSaved: () {},
          ),
        ),
        width: width,
        scale: 2,
      );
      expect(t.takeException(), isNull);
      if (width == 390) {
        await expectLater(
          find.byKey(const Key('final-fitting-preview')),
          matchesGoldenFile('previews/final-fitting-2063.png'),
        );
      }
    });
  }
}
