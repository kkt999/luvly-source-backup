import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/ar_models.dart';
import 'package:luvly_app/src/ar_preview.dart';
import 'package:luvly_app/src/gown_viewer.dart';
import 'package:luvly_app/src/model.dart' show Dress;

void main() {
  const channel = MethodChannel('luvly/ar');
  final princess = resolveArDress('princess-wedding')!;
  for (final model in catalogueArModels) {
    testWidgets(
      '360 entry opens exact model ${model.id}, keeps separate live try-on entry',
      (tester) async {
        MethodCall? received;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            received = call;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.physicalSize = const Size(390, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(home: ArTryOnGuideScreen(dress: model)),
        );
        expect(find.text('Start live try-on'), findsOneWidget);
        await tester.ensureVisible(find.text('360° view'));
        await tester.tap(find.text('360° view'));
        await tester.pump();
        expect(received?.method, 'openGownViewer');
        expect(received?.arguments, {
          'dressId': model.id,
          'modelAsset': model.arAsset,
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('unsupported model is never silently replaced', (tester) async {
    const other = Dress(
      'Unknown gown',
      0,
      'A-Line',
      'unknown',
      'Unknown model',
      id: 'francine-reference',
      arAsset: 'assets/models/princess_wedding.glb',
    );
    expect(supportsGownViewer(other), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GownViewerButton(dress: other)),
      ),
    );
    expect(find.text('360° view'), findsNothing);
  });
  testWidgets('platform error gives retry feedback', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'START_FAILED'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GownViewerButton(dress: princess)),
      ),
    );
    await tester.tap(find.text('360° view'));
    await tester.pump();
    expect(
      find.text('Could not open the 360° view. Please try again.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'non-Android explains availability without native call',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GownViewerButton(dress: princess)),
        ),
      );
      await tester.tap(find.text('360° view'));
      await tester.pump();
      expect(
        find.text('Open the Luvly Android app to explore this dress in 360°.'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
