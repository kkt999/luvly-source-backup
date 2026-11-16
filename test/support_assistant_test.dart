import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/support/assistant_api.dart';
import 'package:luvly_app/support/assistant_screen.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/support/support_screens.dart';
import 'support_flow_test.dart' show MemorySupport;
import 'checkout_redesign_test.dart' show fonts, viewport;

class FakeAssistant implements AssistantApi {
  bool enabled = true, fail = false;
  final calls = <bool>[];
  final contexts = <List<String>>[];
  Completer<AssistantReply>? pending;
  AssistantReply? result;
  @override
  Future<bool> configured() async => enabled;
  @override
  void close() {}
  @override
  Future<AssistantReply> ask({
    required String message,
    required List<String> history,
    required String language,
    required bool ai,
    required String requestId,
  }) async {
    calls.add(ai);
    contexts.add(List.of(history));
    if (fail) throw StateError('Offline');
    if (pending != null) return pending!.future;
    if (result != null) return result!;
    return AssistantReply(
      answer: 'A first 60-minute Dress Trial costs RM50.',
      mode: ai ? 'AI' : 'Guide',
      handoff: true,
      sources: const [
        {'id': 'fitting', 'title': 'Fitting fee'},
      ],
    );
  }
}

Future<void> showAssistant(
  WidgetTester t,
  FakeAssistant api, {
  Future<void> Function(String)? onContact,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: luvlyTheme,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: SupportAssistantScreen(api: api, onContact: onContact),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> chatOption(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('Chat options'));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'starters only fill editable drafts; send still requires consent and starters return after clear',
    (t) async {
      final api = FakeAssistant();
      await showAssistant(t, api);
      final starters = find.byKey(const Key('assistant-question-starters'));
      expect(starters, findsOneWidget);
      for (final question in [
        'How much is a fitting?',
        'How does the deposit work?',
        'When should I book my fitting?',
      ]) {
        await t.tap(find.widgetWithText(OutlinedButton, question));
        await t.pumpAndSettle();
        final field = t.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, question);
        expect(field.controller!.selection.baseOffset, question.length);
        expect(field.focusNode!.hasFocus, true);
        expect(api.calls, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
      }
      await t.enterText(
        find.byType(TextField),
        'How much is a fitting for my first visit?',
      );
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
      await t.pumpAndSettle();
      expect(api.calls, [true]);
      expect(starters, findsNothing);
      expect(
        find.text('How much is a fitting for my first visit?'),
        findsOneWidget,
      );
      await chatOption(t, 'New conversation');
      await t.tap(find.text('Clear chat'));
      await t.pumpAndSettle();
      expect(starters, findsOneWidget);
      expect(api.calls, [true]);
    },
  );
  testWidgets('starter buttons wrap at narrow width and enlarged text', (
    t,
  ) async {
    viewport(t, const Size(320, 720));
    await showAssistant(t, FakeAssistant(), scale: 1.5);
    for (final question in [
      'How much is a fitting?',
      'How does the deposit work?',
      'When should I book my fitting?',
    ]) {
      await t.ensureVisible(find.widgetWithText(OutlinedButton, question));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, question));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        question,
      );
      expect(t.takeException(), isNull);
    }
  });
  test(
    'local reference guide is honestly labelled, localized, and does not match ring inside bring',
    () async {
      final en = await localHelp('How much is a fitting?', [], 'en');
      expect(en.mode, 'Guide');
      expect(en.notice, 'Offline');
      expect(en.answer, contains('RM50'));
      final zh = await localHelp('试穿多少钱？', [], 'auto');
      expect(zh.answer, contains('首次'));
      final ms = await localHelp('berapa bayaran deposit pakej?', [], 'ms');
      expect(ms.answer, contains('50%'));
      final bring = await localHelp('Can I bring my sister?', [], 'en');
      expect(bring.sources.any((s) => s['id'] == 'accessories'), isFalse);
      final privacy = await localHelp('password: secretValue', [], 'en');
      expect(privacy.notice, 'Privacy');
      expect(privacy.answer, isNot(contains('secretValue')));
    },
  );
  testWidgets(
    'AI is off by default; Gemini disclosure and new consent needed before provider use and can be revoked',
    (t) async {
      final api = FakeAssistant();
      await showAssistant(t, api);
      expect(api.calls, isEmpty);
      expect(find.text('Your first fitting'), findsNothing);
      expect(
        find.textContaining('Hi, I’m your Luvly Assistant'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField), 'How much is fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.textContaining('Google Gemini'), findsOneWidget);
      expect(find.textContaining('human reviewers'), findsOneWidget);
      await t.tap(find.text('Use help guide'));
      await t.pumpAndSettle();
      expect(api.calls, [false]);
      await chatOption(t, 'Enable AI');
      await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'How do fittings work?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, [false, true]);
      expect(find.text('Gemini · AI answer'), findsOneWidget);
      await chatOption(t, 'Turn AI off');
      expect(find.text('Help guide · AI is off'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'What is the deposit?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, [false, true, false]);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'transport requires Gemini consent v3 status and sends only bounded user context',
    () async {
      var provider = 'Dialogflow ES', version = 2;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'aiConfigured': true,
              'provider': provider,
              'consentVersion': version,
            }),
            200,
          );
        }
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'answer': 'A natural answer.',
            'mode': 'AI',
            'handoff': false,
            'sources': [
              {
                'id': 'fitting',
                'title': 'Fitting fee',
                'excerpt': 'A first fitting is RM50.',
              },
            ],
          }),
          200,
        );
      });
      final api = LuvlyAssistantApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.trycloudflare.com',
          token: () async => 'test-token',
          client: client,
        ),
      );
      addTearDown(api.close);
      expect(await api.configured(), false);
      provider = 'Gemini';
      version = 3;
      expect(await api.configured(), true);
      final reply = await api.ask(
        message: 'Can that be credited?',
        history: ['How much is fitting?'],
        language: 'en',
        ai: true,
        requestId: 'a' * 32,
      );
      expect(body!['consentVersion'], 3);
      expect(body!['history'], ['How much is fitting?']);
      expect(reply.answer, 'A natural answer.');
      expect(reply.sources.single['excerpt'], 'A first fitting is RM50.');
    },
  );
  testWidgets(
    'dismissing first-send consent keeps the draft and sends nothing',
    (t) async {
      final api = FakeAssistant();
      await showAssistant(t, api);
      await t.enterText(find.byType(TextField), 'How much is fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      Navigator.of(t.element(find.byType(AlertDialog))).pop();
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'How much is fitting?',
      );
      expect(api.calls, isEmpty);
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(find.text('Use AI-assisted answers?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
      await t.pumpAndSettle();
      expect(api.calls, [true]);
      expect(api.contexts.single, isEmpty);
    },
  );
  testWidgets(
    'Gemini answer is displayed as generated, follow-up uses user questions and policy details can be checked',
    (t) async {
      final api = FakeAssistant()
        ..result = const AssistantReply(
          answer:
              'Yes, that RM50 can be credited once after you attend your fitting.',
          mode: 'AI',
          handoff: false,
          sources: [
            {
              'id': 'fitting',
              'title': 'Fitting fee',
              'excerpt':
                  'First fitting RM50. Credit applies once after attendance.',
            },
          ],
        );
      await showAssistant(t, api);
      await t.enterText(find.byType(TextField), 'How much is fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
      await t.pumpAndSettle();
      expect(find.textContaining('Yes, that RM50'), findsOneWidget);
      await t.ensureVisible(find.text('Check Luvly policy details'));
      await t.tap(find.text('Check Luvly policy details'));
      await t.pumpAndSettle();
      expect(
        find.text('First fitting RM50. Credit applies once after attendance.'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField), 'Can that fee be credited?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.contexts.last, ['How much is fitting?']);
      expect(api.calls, [true, true]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unconfigured provider never shows an enable button; failure keeps the question draft',
    (t) async {
      final api = FakeAssistant()
        ..enabled = false
        ..fail = true;
      await showAssistant(t, api);
      expect(find.text('Enable AI'), findsNothing);
      expect(find.textContaining('AI is not connected'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'What is the fitting fee?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'What is the fitting fee?',
      );
      expect(find.textContaining('Try sending it again'), findsOneWidget);
    },
  );
  testWidgets('busy requests cannot duplicate questions or change AI consent', (
    t,
  ) async {
    final api = FakeAssistant()..pending = Completer<AssistantReply>();
    await showAssistant(t, api);
    await chatOption(t, 'Enable AI');
    await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'How much is fitting?');
    await t.tap(find.byTooltip('Send question'));
    await t.pump();
    await t.tap(find.byTooltip('Send question'));
    await t.pump();
    expect(api.calls.length, 1);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    api.pending!.complete(
      const AssistantReply(
        answer: 'Please contact our team.',
        mode: 'Guide',
        handoff: true,
        sources: [],
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'privacy blocks do not reach API or appear in the proposed team transcript',
    (t) async {
      final api = FakeAssistant();
      String? draft;
      await t.runAsync(() => localHelp('password: blocked', [], 'en'));
      await showAssistant(
        t,
        api,
        onContact: (v) async {
          draft = v;
        },
      );
      await t.enterText(find.byType(TextField), 'password: doNotSend123');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(
        find.textContaining('This message was not sent to AI'),
        findsOneWidget,
      );
      await chatOption(t, 'Contact the team');
      expect(draft, isNotNull);
      expect(draft, isNot(contains('doNotSend123')));
    },
  );
  testWidgets(
    'handoff opens an editable ticket draft and does not create a ticket until Send',
    (t) async {
      final api = FakeAssistant(), repo = MemorySupport();
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        SupportScope(
          repository: repo,
          child: MaterialApp(
            home: Builder(
              builder: (context) => SupportAssistantScreen(
                api: api,
                onContact: (draft) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NewSupportTicket(
                        uid: 'a',
                        name: 'Demo bride',
                        initialSubject: 'Assistant follow-up',
                        initialBody: draft,
                        initialCategory: 'Other',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await chatOption(t, 'Enable AI');
      await t.tap(find.text('Use help guide'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'How much is fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      await chatOption(t, 'Contact the team');
      expect(repo.ticket, isNull);
      final field = t.widget<TextFormField>(find.byType(TextFormField).at(1));
      expect(field.controller!.text, contains('How much is fitting?'));
      expect(field.controller!.text, contains('please review before sending'));
      await t.enterText(
        find.byType(TextFormField).at(1),
        'I would like to discuss fitting options.',
      );
      await t.ensureVisible(find.text('Send question'));
      await t.tap(find.text('Send question'));
      await t.pumpAndSettle();
      expect(repo.ticket, isNotNull);
      expect(
        repo.messages.single.body,
        'I would like to discuss fitting options.',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets('assistant phone layout at text scale $scale', (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      final api = FakeAssistant()..enabled = false;
      api.result = await t.runAsync(
        () => localHelp('How much is a fitting?', [], 'en'),
      );
      await showAssistant(t, api, scale: scale, onContact: (_) async {});
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/support-assistant-$scale.png'),
      );
      await t.enterText(find.byType(TextField), 'How much is a fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/support-answer-$scale.png'),
      );
    });
  }
}
