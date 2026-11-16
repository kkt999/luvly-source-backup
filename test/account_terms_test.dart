import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/account_terms.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

Future<void> mount(
  WidgetTester t, {
  bool readOnly = false,
  double scale = 1,
  Size size = const Size(390, 844),
  ValueChanged<bool?>? result,
}) async {
  viewport(t, size);
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => FilledButton(
            onPressed: () async {
              final value = await Navigator.of(c).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RepaintBoundary(
                    key: const Key('terms-capture'),
                    child: AccountTermsScreen(readOnly: readOnly),
                  ),
                ),
              );
              result?.call(value);
            },
            child: const Text('Open notice'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open notice'));
  await t.pumpAndSettle();
}

ScrollController controller(WidgetTester t) => t
    .widget<SingleChildScrollView>(find.byKey(const Key('terms-scroll')))
    .controller!;
Future<void> end(WidgetTester t) async {
  controller(t).jumpTo(controller(t).position.maxScrollExtent);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('terms-capture')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('work/privacy-2115').createSync(recursive: true);
    File(
      'work/privacy-2115/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'opening, scrolling and dismissing never accepts registration terms',
    (t) async {
      bool? result;
      await mount(t, result: (v) => result = v);
      final agree = find.widgetWithText(FilledButton, 'I agree');
      expect(t.widget<FilledButton>(agree).onPressed, isNull);
      await end(t);
      expect(t.widget<FilledButton>(agree).onPressed, isNotNull);
      expect(result, isNull);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      await t.tap(find.text('Open notice'));
      await t.pumpAndSettle();
      await end(t);
      await t.tap(agree);
      await t.pumpAndSettle();
      expect(result, isTrue);
    },
  );
  testWidgets('switching notice language requires reaching the new text end', (
    t,
  ) async {
    bool? result;
    await mount(t, result: (v) => result = v);
    await end(t);
    controller(t).jumpTo(0);
    await t.pumpAndSettle();
    await t.tap(find.text('Bahasa Melayu'));
    await t.pumpAndSettle();
    final agree = find.widgetWithText(FilledButton, 'Saya setuju');
    expect(t.widget<FilledButton>(agree).onPressed, isNull);
    expect(find.text('Maklumat anda, pilihan anda.'), findsOneWidget);
    await end(t);
    await t.tap(agree);
    await t.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets('profile notice is readable without recording a new agreement', (
    t,
  ) async {
    bool? result;
    await mount(t, readOnly: true, result: (v) => result = v);
    expect(find.widgetWithText(FilledButton, 'I agree'), findsNothing);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(result, isFalse);
  });
  for (final large in [false, true]) {
    testWidgets(
      'bilingual notice fits ${large ? 'large text' : 'normal'} phone',
      (t) async {
        await mount(
          t,
          scale: large ? 2 : 1,
          size: Size(large ? 320 : 390, 844),
        );
        await capture(t, large ? 'notice-large-en' : 'notice-en');
        expect(t.takeException(), isNull);
        await t.tap(find.text('Bahasa Melayu'));
        await t.pumpAndSettle();
        await capture(t, large ? 'notice-large-ms' : 'notice-ms');
        expect(t.takeException(), isNull);
        await end(t);
        expect(
          t.getBottomRight(find.widgetWithText(FilledButton, 'Saya setuju')).dy,
          lessThanOrEqualTo(844),
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
