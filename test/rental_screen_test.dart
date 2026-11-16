import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/catalogue/rental_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';

void main() {
  testWidgets(
    'customer sees rental deadline without staff confirmation controls',
    (tester) async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'serverNow': 1000,
            'limited': false,
            'rentals': [
              {
                'id': 'r',
                'state': 'Held',
                'pickupDate': '2026-10-16',
                'eventDate': '2026-10-17',
                'returnDate': '2026-10-18',
                'availableAgain': '2026-10-22',
                'depositCents': 10000,
                'expiresAt': 901000,
                'gowns': [
                  {'dressId': 'g', 'name': 'Ivory gown', 'size': 'M'},
                ],
              },
            ],
          }),
          200,
        ),
      );
      addTearDown(client.close);
      final api = HttpPaymentApi(
        client: client,
        baseUrl: 'https://test.example',
        token: () async => 'token',
      );
      await tester.pumpWidget(MaterialApp(home: RentalScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Awaiting deposit'), findsOneWidget);
      expect(find.text('Ivory gown · Size M'), findsOneWidget);
      expect(find.text('Review rental'), findsNothing);
      expect(find.text('Cancel rental'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('staff cannot submit incomplete rental dates or price', (
    tester,
  ) async {
    int writes = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') writes++;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('rentals')
              ? {'serverNow': 1000, 'limited': false, 'rentals': []}
              : {'dresses': []},
        ),
        200,
      );
    });
    addTearDown(client.close);
    final api = HttpPaymentApi(
      client: client,
      baseUrl: 'https://test.example',
      token: () async => 'token',
    );
    final b = BookingRequest('a', {
      'name': 'Test bride',
      'startAt': Timestamp.now(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: RentalScreen(api: api, appointment: b),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review rental'));
    await tester.tap(find.text('Review rental'));
    await tester.pump();
    expect(writes, 0);
    expect(find.textContaining('Choose a gown, size'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('expired rental invoice cannot start another checkout', () {
    final invoice = SandboxInvoice(
      id: 'x',
      title: 'Deposit',
      appointmentId: 'a',
      amountCents: 10000,
      state: 'Unpaid',
      holdExpiresAt: 1,
    );
    expect(invoice.holdExpired, true);
    expect(invoice.canPay, false);
  });
}
