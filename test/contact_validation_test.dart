import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'package:luvly_app/src/design.dart';
import 'fake_accounts.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

void main() {
  test(
    'names support actual scripts and normal punctuation, reject symbols/digits',
    () {
      for (final name in [
        'Jane Lim',
        '李',
        '张小明',
        "Nur Aisyah binti Ali",
        'Ravi a/l Kumar',
        "Anne-Marie O’Neil",
        "D'Arcy",
        'José',
        'Jose\u0301',
        'محمد علي',
        'லட்சுமி',
        'Alice @ Mei',
      ]) {
        expect(validateName(name), isNull, reason: name);
      }
      for (final name in [
        '',
        '   ',
        '**-+',
        '12345',
        'Jane123',
        'Jane🙂',
        'Jane\nLim',
        'Jane\u200bLim',
        'a' * 101,
      ]) {
        expect(validateName(name), isNotNull, reason: name);
      }
      expect(normalizeContactName('  Jane   Lim  '), 'Jane Lim');
    },
  );
  test(
    'MY inputs normalize without duplicating code, with current national lengths',
    () {
      for (final value in [
        '0123456789',
        '12 345 6789',
        '+60 12-345 6789',
        '60123456789',
        '0060123456789',
        '+60 (0)12 345 6789',
      ]) {
        expect(normalizeMalaysiaPhone(value), '+60123456789', reason: value);
      }
      for (final value in [
        '01112345678',
        '0191234567',
        '01912345678',
        '01590123456',
        '03-2385 6789',
      ]) {
        expect(normalizeMalaysiaPhone(value), isNotNull, reason: value);
      }
      for (final value in [
        '769898989646768',
        '012345678',
        '01012345678',
        '000123456789',
        '+6512345678',
        '+60+60123456789',
        '012abc3456789',
        '12/3456789',
        '1' * 41,
      ]) {
        expect(normalizeMalaysiaPhone(value), isNull, reason: value);
      }
      expect(malaysiaNationalInput('+60 12-345 6789'), '123456789');
      expect(malaysiaNationalInput('+6512345678'), '+6512345678');
    },
  );
  test(
    'session rejects bad contact before creating authentication and normalizes saved data',
    () async {
      final gateway = FakeAccounts();
      final session = AccountSession(gateway);
      addTearDown(session.dispose);
      await session.register(
        'a@example.test',
        'Valid1!password',
        '**-+',
        '0123456789',
      );
      expect(gateway.registerCalls, 0);
      await session.register(
        'a@example.test',
        'Valid1!password',
        'Jane Lim',
        '769898989646768',
      );
      expect(gateway.registerCalls, 0);
      await session.register(
        'a@example.test',
        'Valid1!password',
        '  Jane   Lim  ',
        '012 345 6789',
      );
      expect(gateway.registerCalls, 1);
      expect(gateway.saved!.phone, '+60123456789');
      expect(gateway.saved!.name, 'Jane Lim');
      await expectLater(
        session.updateProfile(
          const BrideProfile(name: '123', phone: '0123456789'),
        ),
        throwsA(isA<ContactValidationException>()),
      );
      expect(gateway.saved!.name, 'Jane Lim');
      expect(
        const BrideProfile(
          name: 'Jane Lim',
          phone: '0123456789',
        ).editable['phone'],
        '+60123456789',
      );
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'registration updates field errors and shows MY code ${large ? 'large' : 'normal'}',
      (t) async {
        viewport(t, Size(large ? 320 : 390, 844));
        await fonts();
        final gateway = FakeAccounts();
        final session = AccountSession(gateway);
        addTearDown(session.dispose);
        await t.pumpWidget(
          AccountScope(
            session: session,
            child: MaterialApp(
              theme: luvlyTheme,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: const RepaintBoundary(
                key: Key('register-artifact'),
                child: AuthScreen(register: true),
              ),
            ),
          ),
        );
        final fields = find.byType(TextFormField);
        await t.enterText(fields.at(0), '**-+');
        await t.pumpAndSettle();
        expect(find.textContaining('normal name punctuation'), findsOneWidget);
        await t.enterText(fields.at(0), '张小明');
        await t.pumpAndSettle();
        expect(find.textContaining('normal name punctuation'), findsNothing);
        await t.enterText(fields.at(2), '769898989646768');
        await t.pumpAndSettle();
        expect(find.textContaining('Enter a valid Malaysian'), findsOneWidget);
        await t.enterText(fields.at(2), '+60 12-345 6789');
        await t.enterText(fields.at(3), 'weak');
        await t.pumpAndSettle();
        expect(
          t.widget<TextFormField>(fields.at(2)).controller!.text,
          '123456789',
        );
        expect(find.text('MY  +60'), findsOneWidget);
        expect(find.textContaining('Use 8–128'), findsOneWidget);
        await t.enterText(fields.at(4), '1234Abc@');
        await t.enterText(fields.at(3), '1234Abc@');
        await t.pumpAndSettle();
        expect(find.textContaining('Use 8–128'), findsNothing);
        expect(find.text('Passwords do not match'), findsNothing);
        await t.enterText(fields.at(3), '1234Abd@');
        await t.pumpAndSettle();
        expect(find.text('Passwords do not match'), findsOneWidget);
        await t.enterText(fields.at(3), '1234Abc@');
        await t.pumpAndSettle();
        expect(find.text('Passwords do not match'), findsNothing);
        expect(gateway.registerCalls, 0);
        expect(t.takeException(), isNull);
        await t.enterText(fields.at(0), 'Jane Lim');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.ensureVisible(fields.at(2));
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('register-artifact')),
          );
          final img = await boundary.toImage();
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory('work/contact-validation-2125').createSync(recursive: true);
          File(
            'work/contact-validation-2125/register-${large ? 'large' : 'normal'}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          img.dispose();
        });
      },
    );
  }
}
