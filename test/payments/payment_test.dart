import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_screen.dart';

const invoiceId = '0123456789abcdef0123456789abcdef';
Map<String, dynamic> data({String state = 'Quoted'}) => {
  'id': invoiceId,
  'title': 'Appointment deposit',
  'appointmentId': 'booking',
  'amountCents': 1000,
  'environment': 'sandbox',
  'state': state,
  if (state != 'Quoted') 'checkoutUrl': 'https://dev.toyyibpay.com/sandbox1',
  if (state == 'SandboxPaid') 'invoiceNo': 'TP_TEST',
};

class FakePayments implements PaymentApi {
  FakePayments({this.configured = true, this.state = 'Quoted'});
  @override
  final bool configured;
  String state;
  int checkouts = 0;
  int lists = 0;
  bool error = false;
  @override
  Future<List<SandboxInvoice>> list() async {
    lists++;
    if (error) throw const PaymentFailure('Unavailable');
    return [SandboxInvoice.fromJson(data(state: state))];
  }

  @override
  Future<SandboxInvoice> checkout(
    String id, {
    String paymentMethod = 'FPX',
  }) async {
    checkouts++;
    state = 'Unpaid';
    return SandboxInvoice.fromJson(data(state: state));
  }

  @override
  Future<SandboxInvoice> refresh(String id) async {
    state = 'SandboxPaid';
    return SandboxInvoice.fromJson(data(state: state));
  }

  @override
  Future<SandboxInvoice> quote(
    String appointmentId,
    String purpose,
    int amountCents,
  ) async => SandboxInvoice.fromJson(data());
  @override
  void close() {}
}

void main() {
  testWidgets(
    'invoice form validates missing appointment and decimal amount at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final booking = BookingRequest('booking', {
        'name': 'Test Bride',
        'status': 'Confirmed',
        'dressId': 'dress',
        'startAt': Timestamp.fromDate(DateTime.utc(2026, 10, 12, 2)),
      });
      InvoiceDraft? draft;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  draft = await showDialog<InvoiceDraft>(
                    context: c,
                    builder: (_) => QuoteDialog(bookings: [booking]),
                  );
                },
                child: const Text('Open quote'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open quote'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Issue invoice'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an appointment'), findsOneWidget);
      expect(find.textContaining('Enter RM 1.00'), findsOneWidget);
      expect(draft, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Test Bride').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '10.001');
      await tester.tap(find.widgetWithText(FilledButton, 'Issue invoice'));
      await tester.pumpAndSettle();
      expect(draft, isNull);
      await tester.enterText(find.byType(TextFormField), '10.01');
      await tester.tap(find.widgetWithText(FilledButton, 'Issue invoice'));
      await tester.pumpAndSettle();
      expect(draft?.appointmentId, 'booking');
      expect(draft?.amountCents, 1001);
      expect(draft?.purpose, 'AppointmentDeposit');
      expect(tester.takeException(), isNull);
    },
  );
  test('exact cents parsing rejects weak numeric input', () {
    expect(quoteAmountCents('10.01'), 1001);
    expect(quoteAmountCents('10.1'), 1010);
    for (final value in [
      '0',
      '0.99',
      '-10',
      '1e2',
      '1.234',
      'abc',
      '1000000.01',
    ]) {
      expect(quoteAmountCents(value), isNull);
    }
  });
  test('checkout URL must be sandbox HTTPS with no redirect parameters', () {
    expect(
      sandboxCheckoutUri('https://dev.toyyibpay.com/sandbox1').host,
      'dev.toyyibpay.com',
    );
    for (final value in [
      'https://toyyibpay.com/live1',
      'http://dev.toyyibpay.com/a',
      'https://dev.toyyibpay.com.evil.example/a',
      'https://user@dev.toyyibpay.com/a',
      'https://dev.toyyibpay.com/a?continue=evil',
      'https://dev.toyyibpay.com/a#evil',
      'https://dev.toyyibpay.com:8080/a',
    ]) {
      expect(() => sandboxCheckoutUri(value), throwsA(isA<PaymentFailure>()));
    }
  });
  test('live states and malformed money cannot be shown as a receipt', () {
    for (final changes in [
      {'environment': 'live'},
      {'state': 'Paid'},
      {'amountCents': 1000.5},
      {'state': 'SandboxPaid'},
      {'checkoutUrl': 'https://evil.example/a'},
    ]) {
      expect(
        () => SandboxInvoice.fromJson({...data(), ...changes}),
        throwsA(isA<PaymentFailure>()),
      );
    }
  });
  test(
    'HTTP checkout sends only invoice ID and a Firebase bearer token',
    () async {
      final api = HttpPaymentApi(
        baseUrl: 'https://payments.example.com',
        token: () async => 'test-token',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/invoices/$invoiceId/checkout');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {'paymentMethod': 'FPX'});
          return http.Response(jsonEncode(data(state: 'Unpaid')), 200);
        }),
      );
      expect((await api.checkout(invoiceId)).state, 'Unpaid');
    },
  );
  test('missing login and non-HTTPS backend never send token', () async {
    final client = MockClient(
      (_) async => throw StateError('must not contact'),
    );
    for (final base in [
      'http://payments.example.com',
      'https://user:pass@example.com',
      'https://example.com?x=1',
    ]) {
      await expectLater(
        HttpPaymentApi(
          baseUrl: base,
          client: client,
          token: () async => 'secret',
        ).list(),
        throwsA(isA<PaymentFailure>()),
      );
    }
    await expectLater(
      HttpPaymentApi(
        baseUrl: 'https://example.com',
        client: client,
        token: () async => null,
      ).list(),
      throwsA(isA<PaymentFailure>()),
    );
  });
  test(
    'gateway errors are shown safely without raw response content',
    () async {
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'test',
        client: MockClient(
          (_) async =>
              http.Response('{"error":"secret upstream content"}', 503),
        ),
      );
      try {
        await api.list();
        fail('must reject');
      } on PaymentFailure catch (error) {
        expect(error.message, isNot(contains('secret upstream')));
      }
    },
  );
  testWidgets(
    'unconfigured screen does not contact service or pretend payment is enabled',
    (tester) async {
      final api = FakePayments(configured: false);
      await tester.pumpWidget(MaterialApp(home: LivePaymentsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(api.lists, 0);
      expect(find.textContaining('currently unavailable'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
    },
  );
  testWidgets(
    'customer reviews amount before checkout and checks verified receipt afterwards',
    (tester) async {
      final api = FakePayments();
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LivePaymentsScreen(
            api: api,
            openCheckout: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay now'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm payment'), findsOneWidget);
      expect(api.checkouts, 0);
      await tester.tap(find.text('FPX online banking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(api.checkouts, 1);
      expect(opened?.host, 'dev.toyyibpay.com');
      expect(find.text('View receipt'), findsNothing);
      await tester.tap(find.text('Check status'));
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      await tester.tap(find.text('View receipt'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Receipt'), findsOneWidget);
      expect(find.text('Demo receipt'), findsNothing);
      expect(find.text('Download PDF'), findsOneWidget);
    },
  );
  testWidgets('cancelled payment confirmation creates no bill', (tester) async {
    final api = FakePayments();
    await tester.pumpWidget(MaterialApp(home: LivePaymentsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.checkouts, 0);
  });
  testWidgets(
    'staff is read-only and review invoices offer no payment button',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LivePaymentsScreen(api: FakePayments(), staff: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Issue invoice'), findsNothing);
      expect(find.text('Pay now'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: LivePaymentsScreen(
            key: const ValueKey('review'),
            api: FakePayments(state: 'ReviewRequired'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review required'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
    },
  );
  testWidgets('manager sees issue action and service failure has retry', (
    tester,
  ) async {
    final api = FakePayments();
    await tester.pumpWidget(
      MaterialApp(
        home: LivePaymentsScreen(api: api, manager: true, staff: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Issue invoice'), findsOneWidget);
    api.error = true;
    await tester.tap(find.byTooltip('Refresh invoices'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Pay now'), findsNothing);
  });

  testWidgets(
    'payment page removes technical banners without making unverified invoices paid',
    (tester) async {
      for (final state in [
        'Quoted',
        'Unpaid',
        'Pending',
        'Creating',
        'ReviewRequired',
        'SandboxPaid',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: LivePaymentsScreen(
              key: ValueKey(state),
              api: FakePayments(state: state),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('TEST PAYMENTS ONLY'), findsNothing);
        expect(find.textContaining('No real money'), findsNothing);
        expect(find.textContaining('Showing up to 100'), findsNothing);
        expect(
          find.text('Paid'),
          state == 'SandboxPaid' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('View receipt'),
          state == 'SandboxPaid' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Pay now'),
          ['Quoted', 'Unpaid', 'Pending'].contains(state)
              ? findsOneWidget
              : findsNothing,
        );
      }
    },
  );
}
