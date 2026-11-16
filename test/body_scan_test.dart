import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/recommendations/body_scan.dart';
import 'package:luvly_app/recommendations/body_scan_screen.dart';
import 'package:luvly_app/recommendations/recommendation_api.dart';
import 'package:luvly_app/recommendations/recommendation_engine.dart';
import 'package:luvly_app/recommendations/recommendation_screen.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/model.dart';
import 'recommendation_engine_test.dart' show gown;
import 'recommendation_screen_test.dart' show PreferenceApi;
import 'checkout_redesign_test.dart' show fonts, viewport;

const scanResult = BodyScan(
  shoulderHipRatio: 1.7,
  torsoShoulderRatio: 1.2,
  sampleCount: 30,
  durationMs: 2400,
  relativeSpread: .01,
  capturedAt: 1793500000000,
);

class FakeScanner extends BodyScanner {
  bool supported = true, fail = false;
  BodyScan? result = scanResult;
  Completer<BodyScan?>? pending;
  int calls = 0;
  @override
  bool get available => supported;
  @override
  Future<BodyScan?> scan() async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) throw PlatformException(code: 'SCAN_INTERRUPTED');
    return result;
  }
}

Future<AppModel> mount(
  WidgetTester t,
  FakeScanner scanner, {
  PreferenceApi? api,
  bool large = false,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  final model = AppModel.live()..accountId = 'bride';
  addTearDown(model.dispose);
  await t.pumpWidget(
    AppScope(
      model: model,
      child: RepaintBoundary(
        key: const Key('scan-artifact'),
        child: MaterialApp(
          theme: luvlyTheme,
          debugShowCheckedModeBanner: false,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => api == null
                        ? BodyScanScreen(scanner: scanner)
                        : BridalPreferencesEditor(
                            api: api,
                            measurementsOnly: true,
                            scanner: scanner,
                          ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
  return model;
}

Future<void> tap(WidgetTester t, Key key) async {
  final f = find.byKey(key);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('scan-artifact')),
    );
    final img = await b.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('work/body-scan-2121').createSync(recursive: true);
    File(
      'work/body-scan-2121/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  test(
    'scan comparison is symmetric repeatability, never an accuracy score',
    () {
      final next = BodyScan.fromJson({
        ...scanResult.toJson(),
        'shoulderHipRatio': 1.8,
        'torsoShoulderRatio': 1.1,
      });
      final forward = BodyScanComparison(scanResult, next);
      final reverse = BodyScanComparison(next, scanResult);
      expect(forward.shoulderHipDifference, closeTo(100 * .1 / 1.75, .000001));
      expect(forward.torsoShoulderDifference, reverse.torsoShoulderDifference);
      expect(BodyScanComparison(next, next).shoulderHipDifference, 0);
      expect(next.toJson().length, 7);
    },
  );
  testWidgets(
    'comparison cancellation and errors preserve chosen scan; explicit previous choice saves only original',
    (t) async {
      final api = PreferenceApi();
      final scanner = FakeScanner();
      await mount(t, scanner, api: api);
      await tap(t, const Key('scan-body-proportions'));
      await tap(t, const Key('start-body-scan'));
      scanner.result = null;
      await tap(t, const Key('compare-body-scan'));
      expect(find.byKey(const Key('body-scan-comparison')), findsNothing);
      scanner.fail = true;
      await tap(t, const Key('compare-body-scan'));
      expect(find.textContaining('interrupted'), findsOneWidget);
      scanner.fail = false;
      scanner.result = BodyScan.fromJson({
        ...scanResult.toJson(),
        'shoulderHipRatio': 1.9,
        'capturedAt': scanResult.capturedAt + 10000,
      });
      await tap(t, const Key('compare-body-scan'));
      await t.ensureVisible(find.byKey(const Key('body-scan-comparison')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('repeatability, not accuracy'),
        findsOneWidget,
      );
      expect(api.saved, isEmpty);
      await tap(t, const Key('keep-previous-body-scan'));
      await tap(t, const Key('accept-body-scan'));
      await tap(t, const Key('save-bridal-preferences'));
      expect(api.saved.single.bodyScan!.toJson(), scanResult.toJson());
    },
  );
  testWidgets(
    'latest comparison chosen explicitly, scroll resets and large text remains usable',
    (t) async {
      final scanner = FakeScanner();
      final api = PreferenceApi();
      await mount(t, scanner, api: api, large: true);
      await tap(t, const Key('scan-body-proportions'));
      await tap(t, const Key('start-body-scan'));
      final next = BodyScan.fromJson({
        ...scanResult.toJson(),
        'shoulderHipRatio': 1.8,
        'capturedAt': scanResult.capturedAt + 10000,
      });
      scanner.result = next;
      await t.scrollUntilVisible(
        find.byKey(const Key('compare-body-scan')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(BodyScanScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(t, const Key('compare-body-scan'));
      expect(t.getTopLeft(find.text('Your scan is ready.')).dy, greaterThan(0));
      await t.scrollUntilVisible(
        find.byKey(const Key('body-scan-comparison')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(BodyScanScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await capture(t, 'comparison-large');
      expect(t.takeException(), isNull);
      expect(api.saved, isEmpty);
      await tap(t, const Key('accept-body-scan'));
      await tap(t, const Key('save-bridal-preferences'));
      expect(api.saved.single.bodyScan!.toJson(), next.toJson());
    },
  );
  test('v2 supports slower phones without weakening legacy validation', () {
    final v2 = {
      ...scanResult.toJson(),
      'algorithmVersion': 'joint-ratios-v2',
      'sampleCount': 15,
      'durationMs': 5000,
    };
    expect(BodyScan.fromJson(v2).valid, isTrue);
    for (final patch in <Map<String, dynamic>>[
      {'sampleCount': 14},
      {'durationMs': 2999},
      {'durationMs': 15001},
      {'relativeSpread': .036},
    ]) {
      expect(() => BodyScan.fromJson({...v2, ...patch}), throwsFormatException);
    }
    expect(
      () => BodyScan.fromJson({...v2, 'algorithmVersion': 'joint-ratios-v1'}),
      throwsFormatException,
    );
    expect(BodyScan.fromJson(scanResult.toJson()).valid, isTrue);
  });
  test(
    'scan schema rejects forged centimetres, unsupported algorithm, nonfinite and unstable results',
    () {
      expect(BodyScan.fromJson(scanResult.toJson()).valid, isTrue);
      for (final patch in <Map<String, dynamic>>[
        {'Bust': 90},
        {'sampleCount': 29},
        {'sampleCount': 91},
        {'sampleCount': 30.5},
        {'durationMs': 1999},
        {'durationMs': 10001},
        {'relativeSpread': .036},
        {'shoulderHipRatio': double.nan},
        {'torsoShoulderRatio': double.infinity},
        {'algorithmVersion': 'ruler'},
        {'capturedAt': 0},
      ]) {
        expect(
          () => BodyScan.fromJson({...scanResult.toJson(), ...patch}),
          throwsFormatException,
        );
      }
      expect(const BridalPreferences(useScanProportions: true).valid, isFalse);
    },
  );
  test(
    'old profiles load; manual measurements and reporting consent survive adding and clearing scan',
    () {
      final old = const BridalPreferences(
        measurements: {'Bust': 90, 'Waist': 65, 'Hips': 92},
        useProportions: true,
        shareProportionStats: true,
        styles: ['Sheath'],
      );
      final withScan = old.withBodyScan(scanResult, true);
      expect(withScan.valid, isTrue);
      expect(proportionGuide(withScan), ProportionGuide.hourglass);
      expect(withScan.measurements, old.measurements);
      expect(withScan.shareProportionStats, isTrue);
      expect(
        BridalPreferences.fromJson(withScan.toJson()).bodyScan!.sampleCount,
        30,
      );
      expect(withScan.withMeasurements({'Height': 165}).bodyScan, isNotNull);
      final clear = withScan.withBodyScan(null, false);
      expect(clear.useScanProportions, isFalse);
      expect(clear.measurements, old.measurements);
      final legacy = old.toJson()
        ..remove('bodyScan')
        ..remove('useScanProportions');
      expect(BridalPreferences.fromJson(legacy).bodyScan, isNull);
    },
  );
  test(
    'scan is opt-in with lower weight; manual guide takes priority without inventing body shape',
    () {
      final dresses = [gown('a', 'Ball Gown'), gown('b', 'Sheath')];
      final savedOnly = const BridalPreferences(bodyScan: scanResult);
      expect(recommendGowns(dresses, savedOnly).first.score, isNull);
      final enabled = const BridalPreferences(
        bodyScan: scanResult,
        useScanProportions: true,
        styles: ['Sheath'],
      );
      expect(proportionGuide(enabled), isNull);
      final result = recommendGowns(dresses, enabled);
      expect(result.first.dress.id, 'b');
      expect(result.first.components.map((c) => c.weight), [60, 15]);
      final manual = enabled.withMeasurements({
        'Bust': 90,
        'Waist': 65,
        'Hips': 92,
      });
      final p = BridalPreferences(
        measurements: manual.measurements,
        useProportions: true,
        bodyScan: scanResult,
        useScanProportions: true,
      );
      final parts = recommendGowns(dresses, p).first.components;
      expect(parts.map((c) => c.label), ['Proportion guide']);
      expect(parts.single.weight, 30);
    },
  );
  testWidgets(
    'review never saves until both acceptance and profile save; removal preserves manual data',
    (t) async {
      final api = PreferenceApi()
        ..row = const PreferenceRecord(
          1,
          BridalPreferences(measurements: {'Bust': 90}, styles: ['Mermaid']),
        );
      final scanner = FakeScanner()
        ..result = BodyScan.fromJson({
          ...scanResult.toJson(),
          'algorithmVersion': 'joint-ratios-v2',
          'sampleCount': 15,
          'durationMs': 5000,
        });
      await mount(t, scanner, api: api);
      await tap(t, const Key('scan-body-proportions'));
      expect(scanner.calls, 0);
      await tap(t, const Key('start-body-scan'));
      expect(find.text('Review your scan'), findsOneWidget);
      expect(api.saved, isEmpty);
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const Key('use-scan-suggestions')),
            )
            .value,
        isFalse,
      );
      await tap(t, const Key('use-scan-suggestions'));
      await tap(t, const Key('accept-body-scan'));
      expect(api.saved, isEmpty);
      final bust = find.byKey(const Key('body-Bust'));
      await t.scrollUntilVisible(
        bust,
        170,
        scrollable: find.byType(Scrollable).first,
      );
      expect(bust, findsOneWidget);
      await tap(t, const Key('save-bridal-preferences'));
      expect(api.saved.single.bodyScan, isNotNull);
      expect(api.saved.single.bodyScan!.algorithmVersion, 'joint-ratios-v2');
      expect(api.saved.single.useScanProportions, isTrue);
      expect(api.saved.single.measurements, {'Bust': 90});
      expect(api.saved.single.styles, ['Mermaid']);
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await tap(t, const Key('remove-body-scan'));
      await tap(t, const Key('save-bridal-preferences'));
      expect(api.saved.last.bodyScan, isNull);
      expect(api.saved.last.measurements, {'Bust': 90});
    },
  );
  testWidgets(
    'cancellation and denied/interrupted scan keep current draft; errors allow retry',
    (t) async {
      final api = PreferenceApi()
        ..row = const PreferenceRecord(
          1,
          BridalPreferences(bodyScan: scanResult),
        );
      final scanner = FakeScanner()..result = null;
      await mount(t, scanner, api: api);
      await tap(t, const Key('scan-body-proportions'));
      await tap(t, const Key('start-body-scan'));
      expect(find.text('Scan proportions'), findsOneWidget);
      scanner.fail = true;
      await tap(t, const Key('start-body-scan'));
      expect(find.textContaining('interrupted'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, const Key('save-bridal-preferences'));
      expect(api.saved.single.bodyScan, isNotNull);
      expect(api.saved.single.useScanProportions, isFalse);
    },
  );
  testWidgets('unsupported device keeps manual form and never invokes camera', (
    t,
  ) async {
    final scanner = FakeScanner()..supported = false;
    await mount(t, scanner);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('start-body-scan')))
          .onPressed,
      isNull,
    );
    expect(scanner.calls, 0);
    expect(find.textContaining('available in the Android app'), findsOneWidget);
  });
  testWidgets('pending camera result cannot be saved into a switched account', (
    t,
  ) async {
    final scanner = FakeScanner()..pending = Completer<BodyScan?>();
    final api = PreferenceApi();
    final model = await mount(t, scanner, api: api);
    await tap(t, const Key('scan-body-proportions'));
    await t.tap(find.byKey(const Key('start-body-scan')));
    await t.pump();
    model.accountId = 'other';
    model.changed();
    await t.pump();
    scanner.pending!.complete(scanResult);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('accept-body-scan')), findsNothing);
    await tap(t, const Key('save-bridal-preferences'));
    expect(api.saved.last.bodyScan, isNull);
  });
  for (final large in [false, true]) {
    testWidgets(
      'scan introduction and result layout ${large ? 'large' : 'normal'}',
      (t) async {
        final scanner = FakeScanner();
        await mount(t, scanner, large: large);
        expect(t.takeException(), isNull);
        await capture(t, 'intro-${large ? 'large' : 'normal'}');
        await tap(t, const Key('start-body-scan'));
        await capture(t, 'review-${large ? 'large' : 'normal'}');
        expect(t.takeException(), isNull);
        await tap(t, const Key('accept-body-scan'));
        expect(t.takeException(), isNull);
      },
    );
  }
}
