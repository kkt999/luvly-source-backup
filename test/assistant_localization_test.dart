import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/support/assistant_api.dart';
import 'package:luvly_app/support/assistant_strings.dart';
import 'assistant_history_test.dart'
    show ChatFixture, mount, open, tap, typeQuestion;
import 'support_assistant_test.dart' show FakeAssistant;

Future<void> menuChoice(
  WidgetTester tester,
  String tooltip,
  String option,
) async {
  await tap(tester, find.byTooltip(tooltip));
  await tap(tester, find.text(option));
}

void main() {
  test('Auto resolves the interface separately from the reply language', () {
    expect(
      assistantUiLanguage(
        'auto',
        application: const Locale('en'),
        device: const [Locale('zh')],
      ),
      'en',
    );
    expect(
      assistantUiLanguage(
        'auto',
        application: const Locale('de'),
        device: const [Locale('ms', 'MY')],
      ),
      'ms',
    );
    expect(assistantUiLanguage('auto', device: const [Locale('fr')]), 'en');
    expect(assistantUiLanguage('zh', application: const Locale('ms')), 'zh');
    expect(assistantGuideLanguage('auto', '试穿需要多少钱？', []), 'zh');
    expect(
      assistantGuideLanguage(
        'auto',
        'Bilakah saya patut menempah sesi mencuba gaun?',
        [],
      ),
      'ms',
    );
    expect(
      assistantGuideLanguage('auto', 'What is the deposit?', ['试穿需要多少钱？']),
      'en',
    );
    expect(assistantGuideLanguage('auto', 'RM50?', ['试穿需要多少钱？']), 'zh');
    expect(
      assistantGuideLanguage('ms', 'How much does fitting cost?', []),
      'ms',
    );
  });

  testWidgets(
    'switch to Chinese immediately, retain draft and existing messages, and restore the saved preference',
    (tester) async {
      final server = ChatFixture();
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(tester, session, assistant: FakeAssistant());
      await open(tester);
      expect(find.text('How much is a fitting?'), findsOneWidget);
      await typeQuestion(tester, 'Original English question');
      await tap(tester, find.byTooltip('Send question'));
      await tap(tester, find.text('Enable AI'));
      final id = server.active;
      final original = Map.of(server.turns[id]!.single);
      await typeQuestion(tester, 'Draft stays');

      server.heldLanguageChange = Completer<void>();
      await tap(tester, find.byTooltip('Chat options'));
      await tester.tap(find.text('中文'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final input = find.byType(TextField);
      expect(
        tester.widget<TextField>(input).decoration!.hintText,
        '向 Luvly 提问…',
      );
      expect(tester.widget<TextField>(input).controller!.text, 'Draft stays');
      expect(server.rooms[id]!['language'], 'auto');
      server.heldLanguageChange!.complete();
      await tester.pumpAndSettle();
      expect(server.rooms[id]!['language'], 'zh');
      expect(find.byTooltip('发送问题'), findsOneWidget);
      await typeQuestion(tester, '可以抵扣订金吗？');
      await tap(tester, find.byTooltip('发送问题'));
      expect(server.sentBodies.last['language'], 'zh');
      expect(server.sentBodies.last['mode'], 'AI');
      expect(server.active, id);
      expect(server.turns[id]!.first, original);
      expect(find.text('Original English question'), findsOneWidget);

      await tap(tester, find.byTooltip('关闭助手'));
      await open(tester);
      expect(find.byTooltip('聊天记录'), findsOneWidget);
      await tap(tester, find.byTooltip('关闭助手'));
      session.dispose();
      final restarted = server.session('customer');
      addTearDown(restarted.dispose);
      await mount(tester, restarted);
      await open(tester);
      expect(find.byTooltip('聊天选项'), findsOneWidget);
      expect(find.text('Original English question'), findsOneWidget);
      expect(find.text('可以抵扣订金吗？'), findsOneWidget);
      await menuChoice(tester, '聊天选项', 'English');
      expect(find.byTooltip('Chat options'), findsOneWidget);
      expect(server.rooms[id]!['language'], 'en');
      expect(server.turns[id]!.first, original);
      expect(server.rooms.length, 1);
    },
  );

  testWidgets(
    'Malay welcome, suggestions, consent and history fit a narrow phone with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(330, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = ChatFixture();
      final session = server.session('customer');
      addTearDown(session.dispose);
      String? supportDraft;
      await mount(
        tester,
        session,
        textScale: 1.45,
        assistant: FakeAssistant(),
        onContact: (draft) async => supportDraft = draft,
      );
      await open(tester);
      await menuChoice(tester, 'Chat options', 'Bahasa Melayu');
      expect(find.textContaining('Hai! Saya Pembantu Luvly.'), findsOneWidget);
      final suggested = find.text('Berapakah bayaran sesi mencuba gaun?');
      await tester.ensureVisible(suggested);
      await tap(tester, suggested);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Berapakah bayaran sesi mencuba gaun?',
      );
      await tap(tester, find.byTooltip('Hantar soalan'));
      expect(find.text('Guna jawapan berbantu AI?'), findsOneWidget);
      expect(find.textContaining('Penyemak manusia'), findsOneWidget);
      await tap(tester, find.text('Hidupkan AI'));
      expect(server.sentBodies.single['language'], 'ms');
      expect(
        server.sentBodies.single['message'],
        'Berapakah bayaran sesi mencuba gaun?',
      );
      expect(server.sentBodies.single['mode'], 'AI');
      await menuChoice(tester, 'Pilihan perbualan', 'Hubungi pasukan Luvly');
      expect(
        supportDraft,
        contains('Pelanggan: Berapakah bayaran sesi mencuba gaun?'),
      );
      await tap(tester, find.byTooltip('Sejarah perbualan'));
      expect(find.text('Sejarah perbualan'), findsOneWidget);
      expect(find.text('Cari perbualan'), findsOneWidget);
      expect(find.text('Diarkibkan'), findsOneWidget);
      await tap(tester, find.byTooltip('Perbualan baharu'));
      expect(server.active, isNull);
      expect(server.rooms.length, 1);
      expect(find.byTooltip('Hantar soalan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Chinese history actions and errors use Chinese and preserve stored content',
    (tester) async {
      final server = ChatFixture()..defaultLanguage = 'zh';
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(tester, session);
      await open(tester);
      expect(find.text('试穿需要多少钱？'), findsOneWidget);
      final suggestion = find.text('婚纱配套订金如何计算？');
      await tap(tester, suggestion);
      await tap(tester, find.byTooltip('发送问题'));
      final id = server.active;
      final original = Map.of(server.turns[id]!.single);
      await tap(tester, find.byTooltip('聊天记录'));
      await tap(tester, find.byTooltip('「Fitting fees」的选项'));
      await tap(tester, find.text('重命名'));
      final title = find.widgetWithText(TextField, '对话标题');
      await tester.enterText(title, '我的试穿记录');
      await tester.pumpAndSettle();
      await tap(tester, find.text('保存标题'));
      expect(server.rooms[id]!['title'], '我的试穿记录');
      await tap(tester, find.byTooltip('「我的试穿记录」的选项'));
      await tap(tester, find.text('归档'));
      expect(find.text('对话已归档。'), findsOneWidget);
      await tap(tester, find.text('已归档'));
      await tap(tester, find.byTooltip('「我的试穿记录」的选项'));
      await tap(tester, find.text('恢复'));
      await tap(tester, find.text('最近'));
      expect(server.turns[id]!.single, original);
      await tap(tester, find.byTooltip('「我的试穿记录」的选项'));
      await tap(tester, find.text('删除'));
      expect(find.text('删除这段对话？'), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(server.turns[id]!.single, original);
      await tap(tester, find.byTooltip('「我的试穿记录」的选项'));
      await tap(tester, find.text('删除'));
      await tap(tester, find.text('永久删除'));
      expect(server.turns[id], isNull);
      expect(find.text('对话已删除。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Auto uses the device locale and keeps its interface after a different-language question',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('ms', 'MY'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final server = ChatFixture();
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(tester, session);
      await open(tester);
      expect(find.byTooltip('Pilihan perbualan'), findsOneWidget);
      await typeQuestion(tester, '试穿需要多少钱？');
      await tap(tester, find.byTooltip('Hantar soalan'));
      expect(server.sentBodies.single['language'], 'auto');
      expect(find.byTooltip('Pilihan perbualan'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        'Tanya Luvly…',
      );

      server.failLanguageChange = true;
      await menuChoice(tester, 'Pilihan perbualan', 'English');
      expect(
        find.text('Pilihan bahasa tidak dapat disimpan. Sila cuba lagi.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Pilihan perbualan'), findsOneWidget);
    },
  );
}
