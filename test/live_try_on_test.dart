import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/live_try_on.dart';
import 'package:luvly_app/src/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dress in dresses.where((d) => d.arAsset != null)) {
    testWidgets('opens exact native model for ${dress.id}', (tester) async {
      MethodCall? received;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('luvly/ar'),
        (call) async {
          received = call;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('luvly/ar'),
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openLiveTryOn(context, dress: dress),
              child: const Text('Try'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Try'));
      await tester.pump();
      expect(received?.method, 'openTryOn');
      expect(received?.arguments, {
        'dressId': dress.id,
        'modelAsset': dress.arAsset,
      });
    });
  }
  testWidgets('unmapped dress never opens a substitute AR model', (
    tester,
  ) async {
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('luvly/ar'),
      (_) async {
        calls++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('luvly/ar'),
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openLiveTryOn(context, dress: dresses.first),
              child: const Text('Try'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Try'));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('AR preview unavailable'), findsOneWidget);
  });
}
