import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/catalogue/gown_measurements.dart';
import 'package:luvly_app/payments/payment_api.dart';

const ranges = {
  'bustMin': 80,
  'bustMax': 90,
  'waistMin': 60,
  'waistMax': 70,
  'hipMin': 90,
  'hipMax': 100,
  'lengthCm': 150,
};
void main() {
  test(
    'size recommendation requires all three ranges and ranks overlapping fits',
    () {
      final variants = <Map<String, dynamic>>[
        {'size': 'M', 'measurements': ranges},
        {
          'size': 'S',
          'measurements': {...ranges, 'bustMax': 84},
        },
        {'size': 'XS', 'measurements': null},
        {
          'size': 'L',
          'measurements': {
            ...ranges,
            'bustMin': 83,
            'bustMax': 87,
            'waistMin': 63,
            'waistMax': 67,
            'hipMin': 93,
            'hipMax': 97,
          },
        },
      ];
      expect(
        matchingGownSizes(variants, {
          'bust': 85,
          'waist': 65,
          'hip': 95,
        }).map((v) => v['size']),
        ['L', 'M'],
      );
      expect(
        matchingGownSizes(variants, {'bust': 85, 'waist': 80, 'hip': 95}),
        isEmpty,
      );
      expect(
        matchingGownSizes(variants, {'bust': 50, 'waist': 60, 'hip': 50}),
        isEmpty,
      );
      expect(matchingGownSizes(variants, {}), isEmpty);
      expect(
        matchingGownSizes(variants, {
          'bust': 90,
          'waist': 70,
          'hip': 100,
        }).single['size'],
        'M',
      );
    },
  );
  test('demo provenance is clearly labelled', () {
    expect(
      measurementSourceLabel({'measurementSource': 'demo-reference'}),
      contains('not measured on this gown'),
    );
    expect(measurementSourceLabel({}), startsWith('Staff-entered'));
  });
  test(
    'fit comparisons use gown-specific inclusive ranges; missing data is never a match',
    () {
      expect(
        fitComparison(ranges, {'bust': 80, 'waist': 70, 'hip': 95}),
        startsWith('Within'),
      );
      expect(
        fitComparison(ranges, {'bust': 91, 'waist': 65, 'hip': 89}),
        'Outside listed range: bust, hip',
      );
      expect(
        fitComparison(null, {'bust': 80, 'waist': 70, 'hip': 95}),
        'Size measurements not provided',
      );
      expect(fitComparison(ranges, {}), startsWith('Enter'));
      for (final input in ['NaN', 'Infinity', '19', '301', '90.55', '-90']) {
        expect(measurementNumber(input), isNull);
      }
      expect(measurementNumber('90.5'), 90.5);
    },
  );
  testWidgets(
    'body measurements stay local and unknown sizes do not fabricate a recommendation',
    (tester) async {
      final requests = <http.Request>[];
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              'variants': [
                {'size': 'M', 'measurements': ranges},
                {'size': 'S', 'measurements': null},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: GownFitScreen(
            dressId: 'gown',
            dressName: 'Example gown',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Find my size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my size'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Enter 20–300 cm, with up to 1 decimal.'),
        findsNWidgets(3),
      );
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextFormField).at(i),
          ['85', '65', '95'][i],
        );
      }
      await tester.ensureVisible(find.text('Find my size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my size'));
      await tester.pumpAndSettle();
      expect(find.text('Your reference size: M'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.textContaining('Size M\nWithin'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Within the listed ranges · fitting still required'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Within the listed ranges · fitting still required'),
        findsOneWidget,
      );
      expect(requests.length, 1);
      expect(requests.single.method, 'GET');
      expect(requests.single.body, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing measurements produces an explicit comparison dialog', (
    tester,
  ) async {
    final api = HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'variants': [
              {'size': 'M', 'measurements': null},
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: GownFitScreen(dressId: 'gown', dressName: 'Example', api: api),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), '50');
    }
    await tester.ensureVisible(find.text('Find my size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find my size'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot compare yet'), findsOneWidget);
    expect(
      find.textContaining('This gown has no size measurements yet.'),
      findsOneWidget,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recommendation can be used; poor fits offer no size to select', (
    tester,
  ) async {
    final api = HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'variants': [
              {'size': 'M', 'measurements': ranges},
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.close);
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GownFitScreen(
                      dressId: 'gown',
                      dressName: 'Example',
                      api: api,
                      returnSize: true,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byType(TextFormField).at(i),
        ['50', '60', '50'][i],
      );
    }
    await tester.ensureVisible(find.text('Find my size'));
      await tester.pumpAndSettle();
    await tester.tap(find.text('Find my size'));
    await tester.pumpAndSettle();
    expect(find.text('Staff fitting recommended'), findsOneWidget);
    expect(find.text('Use M'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byType(TextFormField).at(i),
        ['85', '65', '95'][i],
      );
    }
    await tester.ensureVisible(find.text('Find my size'));
      await tester.pumpAndSettle();
    await tester.tap(find.text('Find my size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use M'));
    await tester.pumpAndSettle();
    expect(chosen, 'M');
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
