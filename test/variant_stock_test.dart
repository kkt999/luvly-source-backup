import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/catalogue/variant_stock_screen.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/payments/payment_api.dart';

const dress = CatalogueDress(
  id: 'gown',
  name: 'Test gown',
  category: 'A-Line',
  description: 'Test gown description.',
  colour: 'White',
  sizes: 'M',
  priceCents: 10000,
  imageUrl: '',
);

void main() {
  testWidgets(
    'measurement editor rejects reversed ranges and saves verified values',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      Map<String, dynamic>? measurements;
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            writes.add(jsonDecode(r.body));
            measurements = Map<String, dynamic>.from(
              writes.last['measurements'],
            );
          }
          return http.Response(
            jsonEncode({
              'variants': [
                {
                  'size': 'M',
                  'quantity': 2,
                  'revision': 1,
                  'measurements': measurements,
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: VariantStockScreen(dress: dress, api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit measurements'));
      await tester.pumpAndSettle();
      final values = ['80', '70', '60', '70', '90', '100', '150'];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      await tester.tap(find.text('Save measurements'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(
        find.text('Maximum must be at least the minimum.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '90');
      await tester.tap(find.text('Save measurements'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(writes.single['quantity'], 2);
      expect(writes.single['measurements']['bustMax'], 90);
      expect(
        find.text('Staff-entered ranges · fitting required'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown quantity is not zero; invalid quantities cannot be saved',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      int? quantity;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          writes.add(jsonDecode(request.body));
          quantity = writes.last['quantity'];
        }
        return http.Response(
          jsonEncode({
            'variants': [
              {
                'dressId': 'gown',
                'size': 'M',
                'quantity': quantity,
                'revision': 0,
              },
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final api = HttpPaymentApi(
        baseUrl: 'https://test.example',
        client: client,
        token: () async => 'token',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VariantStockScreen(dress: dress, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not configured'), findsOneWidget);
      await tester.tap(find.text('Edit quantity'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '-1');
      await tester.tap(find.text('Save quantity'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Enter a whole number from 0 to 100.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '2');
      await tester.tap(find.text('Save quantity'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(writes.single, {
        'dressId': 'gown',
        'size': 'M',
        'quantity': 2,
        'revision': 0,
      });
      expect(find.text('2 total physical gowns'), findsOneWidget);
    },
  );
}
