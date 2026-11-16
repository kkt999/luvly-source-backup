import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/packages/rental_handover_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package_rental_test.dart' show selection;
import 'package_test.dart' show phone;

void main() {
  testWidgets(
    'new package deposit is fixed at 50% with one paid fitting credit; no arbitrary deposit input',
    (t) async {
      phone(t);
      final s = selection();
      s.data['paymentPolicyVersion'] = 1;
      s.data['appointments'][0]['status'] = 'Completed';
      s.data['appointments'][0]['availableCreditCents'] = 5000;
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'token',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: PackageRentalScreen(selection: s, api: api, staff: true),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.textContaining('Booking deposit to pay now:'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(
        find.text('Booking deposit to pay now: RM 399.50'),
        findsOneWidget,
      );
      expect(find.text('Balance before pickup: RM 449.50'), findsOneWidget);
      expect(
        find.textContaining('Separate refundable security: RM 300.00'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'return form rejects missing-item confirmation and non-documented deductions before posting',
    (t) async {
      phone(t);
      var posts = 0;
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((_) async {
          posts++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: RentalHandoverScreen(
            api: api,
            rental: {
              'id': 'rental',
              'pickupDate': '2026-10-16',
              'returnDate': '2026-10-18',
              'gowns': [],
              'balanceCents': 44950,
              'paymentState': 'Paid',
              'securityCents': 30000,
              'securityState': 'Paid',
              'collectedAt': 1,
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Save inspection'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save inspection'));
      await t.pumpAndSettle();
      expect(posts, 0);
      expect(
        find.textContaining('Confirm every item was returned.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'specific new invoice remains visible even when omitted from the capped invoice list',
    (t) async {
      const id = '0123456789abcdef0123456789abcdef';
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path == '/v1/invoices'
                  ? {'invoices': []}
                  : {
                      'id': id,
                      'title': 'First gown fitting',
                      'purpose': 'FittingFee',
                      'appointmentId': 'booking',
                      'amountCents': 5000,
                      'state': 'Quoted',
                      'environment': 'sandbox',
                    },
            ),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: LivePaymentsScreen(api: api, initialInvoiceId: id),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('First gown fitting'), findsOneWidget);
      expect(find.text('RM 50.00'), findsOneWidget);
      expect(find.text('Pay now'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test('cancelled fitting invoices cannot be paid from client controls', () {
    final i = SandboxInvoice.fromJson({
      'id': '0123456789abcdef0123456789abcdef',
      'title': 'Fitting fee',
      'appointmentId': 'booking',
      'amountCents': 5000,
      'state': 'Unpaid',
      'paymentBlocked': true,
      'environment': 'sandbox',
    });
    expect(i.canPay, false);
  });
}
