import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/recommendations/body_measurement_scan_screen.dart';
import 'package:luvly_app/recommendations/body_scan.dart';

class MeasurementScanner extends BodyScanner {
  double? height;
  @override
  bool get available => true;
  @override
  Future<Map<String, double>> estimateMeasurements(double heightCm) async {
    height = heightCm;
    return {'Bust': 92, 'Waist': 72, 'Hips': 99};
  }
}

void main() {
  testWidgets('estimates are editable and copy only after a tape check', (
    t,
  ) async {
    final scanner = MeasurementScanner();
    Map<String, double>? returned;
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                returned = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BodyMeasurementScanScreen(
                      scanner: scanner,
                      initialHeight: '',
                    ),
                  ),
                );
              },
              child: const Text('Open scan'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open scan'));
    await t.pumpAndSettle();
    Future<void> tapVisible(Finder finder) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder.hitTestable());
      await t.pumpAndSettle();
    }

    await tapVisible(find.text('Start measurement scan'));
    expect(scanner.height, isNull);
    final height = find.byKey(const ValueKey('girth-height'));
    await t.ensureVisible(height);
    await t.pumpAndSettle();
    await t.enterText(height, '168');
    await tapVisible(find.text('Start measurement scan'));
    expect(scanner.height, 168);
    expect(find.text('Estimated measurements'), findsOneWidget);
    final use = find.widgetWithText(FilledButton, 'Use checked measurements');
    expect(t.widget<FilledButton>(use).onPressed, isNull);
    expect(returned, isNull);
    final waist = find.byKey(const ValueKey('girth-Waist'));
    await t.ensureVisible(waist);
    await t.pumpAndSettle();
    await t.enterText(waist, '74.5');
    await tapVisible(find.text('I checked these measurements with a tape.'));
    await tapVisible(use);
    expect(returned, {'Bust': 92, 'Waist': 74.5, 'Hips': 99});
    expect(t.takeException(), isNull);
  });
}
