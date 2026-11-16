import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/saved_looks.dart';

void main() {
  const channel = MethodChannel('luvly/ar');
  final image = File('design/dresses/phone_fixture.png').absolute.path;
  Map<String, Object> row(String id) => {
    'id': id,
    'dressId': 'princess-wedding',
    'path': image,
    'savedAt': 1790800000000,
    'fullBody': false,
  };
  Future<void> show(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      AppScope(
        model: AppModel(),
        child: MaterialApp(theme: luvlyTheme, home: screen),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('empty history has no sample photo or fit score', (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [],
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await show(t, const TryOnHistoryScreen());
    expect(find.text('Your looks, all together'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('90 / 100'), findsNothing);
  });
  testWidgets('deletion requires confirmation and exact saved identifier', (
    t,
  ) async {
    final calls = <MethodCall>[];
    var rows = [row('look-one')];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'deleteLook') {
        rows = [];
        return true;
      }
      return rows;
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await show(t, const TryOnHistoryScreen());
    await t.ensureVisible(find.text('Delete'));
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.method == 'deleteLook'), isEmpty);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Delete').last);
    await t.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'deleteLook').arguments, {
      'id': 'look-one',
    });
    expect(find.text('Your looks, all together'), findsOneWidget);
  });
  testWidgets('two real saved looks can be selected and compared', (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [row('one'), row('two')],
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await show(t, const TryOnHistoryScreen());
    for (var i = 0; i < 2; i++) {
      await t.ensureVisible(find.byType(CheckboxListTile).at(i));
      await t.tap(find.byType(CheckboxListTile).at(i));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Compare two looks'));
    await t.pumpAndSettle();
    expect(find.text('Compare your looks'), findsOneWidget);
    expect(find.text('Inspect look'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
