import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/calendar_screen.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Map<String, dynamic> data, {
    int code = 200,
  }) async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode(data), code),
    );
    final api = HttpPaymentApi(
      baseUrl: 'https://backend.example',
      client: client,
      token: () async => 'test',
    );
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: CalendarScreen(api: api)));
    await tester.pumpAndSettle();
  }

  testWidgets('disabled backend shows setup status without connect action', (
    tester,
  ) async {
    await show(tester, {
      'configured': false,
      'connected': false,
      'state': 'Setup required',
    });
    expect(find.text('Status: Setup required'), findsOneWidget);
    expect(find.text('Connect Google Calendar'), findsNothing);
  });
  testWidgets('configured disconnected account can start consent', (
    tester,
  ) async {
    await show(tester, {
      'configured': true,
      'connected': false,
      'state': 'Not connected',
    });
    expect(find.text('Connect Google Calendar'), findsOneWidget);
    await tester.tap(find.text('Connect Google Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Google Calendar?'), findsOneWidget);
  });
  testWidgets('connection failure leaves bookings unchanged and offers retry', (
    tester,
  ) async {
    await show(tester, {}, code: 503);
    expect(
      find.textContaining('Your appointment has not been changed'),
      findsOneWidget,
    );
    expect(find.text('Check status'), findsOneWidget);
  });
}
