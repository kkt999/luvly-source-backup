import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/email_typo_suggestion.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

void main() {
  test('only explicit common-domain typos get optional suggestions', () {
    expect(suggestEmailSpelling('Hs@gmail.con'), 'Hs@gmail.com');
    expect(suggestEmailSpelling('  Me+tag@GMAIL.CON  '), 'Me+tag@gmail.com');
    expect(suggestEmailSpelling('me@gamil.com'), 'me@gmail.com');
    expect(suggestEmailSpelling('me@hotmial.com'), 'me@hotmail.com');
    expect(suggestEmailSpelling('me@outlook.con'), 'me@outlook.com');
    for (final email in [
      'me@gmail.com',
      'me@company.com.my',
      'me@university.edu.my',
      'me@custom.con',
      'me@sub.gmail.con',
      'me@yahoo.com.my',
      'me@icloud.com',
      'me@',
      'me@@gmail.con',
      'me @gmail.con',
      '${'a' * 245}@gmail.con',
    ]) {
      expect(suggestEmailSpelling(email), isNull, reason: email);
    }
  });

  for (final large in [false, true]) {
    testWidgets('registration spelling hint is opt-in and wraps ($large)', (
      t,
    ) async {
      viewport(t, Size(large ? 320 : 390, 844));
      await fonts();
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: Key('email-artifact'),
            child: AuthScreen(register: true),
          ),
        ),
      );
      final emailField = find.byType(TextFormField).at(1);
      final controller = t.widget<TextFormField>(emailField).controller!;
      await t.enterText(emailField, 'Hs@gmail.con');
      await t.pumpAndSettle();
      final hint = find.textContaining('Did you mean ', findRichText: true);
      expect(hint, findsOneWidget);
      expect(controller.text, 'Hs@gmail.con');
      expect(
        t.widget<TextFormField>(emailField).validator!('Hs@gmail.con'),
        isNull,
      );
      await t.ensureVisible(hint);
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('email-artifact')),
        );
        final img = await boundary.toImage();
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('work/email-suggestion-2126').createSync(recursive: true);
        File(
          'work/email-suggestion-2126/${large ? 'large' : 'normal'}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        img.dispose();
      });
      await t.tap(hint);
      await t.pumpAndSettle();
      expect(controller.text, 'Hs@gmail.com');
      expect(controller.selection.baseOffset, 'Hs@gmail.com'.length);
      expect(hint, findsNothing);
      await t.enterText(emailField, 'me@company.com.my');
      await t.pumpAndSettle();
      expect(controller.text, 'me@company.com.my');
      expect(hint, findsNothing);
      await t.enterText(emailField, '${'x' * 64}@gmail.con');
      await t.pumpAndSettle();
      await t.ensureVisible(hint);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('login never suggests changing an existing account identifier', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(theme: luvlyTheme, home: const AuthScreen()),
    );
    await t.enterText(find.byType(TextFormField).first, 'Hs@gmail.con');
    await t.pumpAndSettle();
    expect(find.byType(EmailTypoSuggestion), findsNothing);
  });

  testWidgets('disabled suggestion cannot change the submitted email', (
    t,
  ) async {
    final controller = TextEditingController(text: 'Hs@gmail.con');
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmailTypoSuggestion(controller: controller, enabled: false),
        ),
      ),
    );
    expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(controller.text, 'Hs@gmail.con');
  });
}
