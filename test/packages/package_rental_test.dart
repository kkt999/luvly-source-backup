import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_rental_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package_test.dart' show phone;

PackageSelection selection() => PackageSelection({
  'id': 'selection',
  'name': 'Bridal Essentials',
  'customerName': 'Demo Bride',
  'totalCents': 89900,
  'services': [],
  'selectedGowns': [
    {'dressId': 'gown', 'name': 'Ivory gown', 'size': 'M'},
  ],
  'selectedAccessories': [],
  'rentalPlan': {
    'pickupDate': '2026-10-16',
    'eventDate': '2026-10-17',
    'returnDate': '2026-10-18',
  },
  'rentalPlanRevision': 2,
  'appointments': [
    {
      'id': 'appointment',
      'status': 'Confirmed',
      'type': 'Dress Trial',
      'startAt': 1792116000000,
    },
  ],
});
void main() {
  testWidgets(
    'selecting a completed fitting links it without starting checkout',
    (tester) async {
      phone(tester);
      final requests = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.method == 'GET'
                  ? {
                      'visits': [
                        {
                          'id': 'past-visit',
                          'attendedAt': 1792116000000,
                          'creditCents': 5000,
                        },
                      ],
                    }
                  : {'linked': true},
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final saved = selection();
      saved.data['appointments'] = [];
      await tester.pumpWidget(
        MaterialApp(
          home: PackageRentalScreen(
            selection: saved,
            api: HttpPackageApi(transport: transport),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final link = find.text('Use a completed fitting');
      await tester.scrollUntilVisible(
        link,
        170,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(requests.single.method, 'GET');
      expect(find.textContaining('60-minute fitting'), findsNothing);
      expect(find.text('Select a completed fitting'), findsNothing);
      await tester.tap(find.text('Select completed fitting'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          SimpleDialogOption,
          paymentDateLabel(1792116000000),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.single.method, 'GET');
      expect(find.text('Continue with selected fitting'), findsOneWidget);
      await tester.ensureVisible(find.text('Visit for a fitting'));
      await tester.tap(find.text('Visit for a fitting'));
      await tester.pumpAndSettle();
      expect(find.text('Save fitting preference'), findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('Continue with selected fitting'), findsOneWidget);
      await tester.tap(find.text('Continue with selected fitting'));
      await tester.pumpAndSettle();
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(
        requests.every((r) => r.url.path.endsWith('/completed-fitting')),
        isTrue,
      );
      expect(jsonDecode(requests.last.body), {
        'appointmentId': 'past-visit',
        'planRevision': 2,
        'selectionRevision': 0,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer reuses saved dates without another plan write before fitting booking',
    (tester) async {
      phone(tester);
      http.Request? request;
      Map<String, String>? bookingDates;
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          request = r;
          return http.Response(
            jsonEncode({
              'available': true,
              'items': [],
              'availability': [
                {'remaining': 1},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PackageRentalScreen(
            selection: selection(),
            api: HttpPackageApi(transport: transport),
            onBookFitting: (dates) async {
              bookingDates = dates;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Choose fitting time'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose fitting time'));
      await tester.pumpAndSettle();
      expect(
        request!.url.path,
        '/v1/package-selections/selection/fitting-choice',
      );
      expect(jsonDecode(request!.body), {
        'mode': 'TryOn',
        'accepted': false,
        'revision': 0,
      });
      expect(bookingDates, {
        'pickupDate': '2026-10-16',
        'eventDate': '2026-10-17',
        'returnDate': '2026-10-18',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'staff chooses deposit, sees credited balance and sends a stable confirmation identity',
    (tester) async {
      phone(tester);
      final requests = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({'error': 'INVENTORY_NOT_CONFIGURED'}),
            409,
          );
        }),
      );
      addTearDown(transport.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PackageRentalScreen(
            selection: selection(),
            api: HttpPackageApi(transport: transport),
            staff: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Dress Trial').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '100');
      await tester.pumpAndSettle();
      expect(find.text('Remaining balance: RM 799.00'), findsOneWidget);
      final button = find.text('Confirm & hold for 15 minutes');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[0].body, requests[1].body);
      expect(jsonDecode(requests.first.body)['depositCents'], 10000);
      expect(jsonDecode(requests.first.body)['planRevision'], 2);
      expect(tester.takeException(), isNull);
    },
  );
}
