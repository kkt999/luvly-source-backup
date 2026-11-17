import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/support/assistant_history_api.dart';
import 'package:luvly_app/support/assistant_launcher.dart';
import 'support_assistant_test.dart' show FakeAssistant, chatOption;

class ChatFixture {
  ChatFixture() {
    client = MockClient(handle);
  }
  late final MockClient client;
  final rooms = <String, Map<String, dynamic>>{};
  final turns = <String, List<Map<String, dynamic>>>{};
  final submissions = <String>[];
  final sentBodies = <Map<String, dynamic>>[];
  String? active;
  String defaultLanguage = 'auto';
  bool failLanguageChange = false;
  bool failNextSend = false, failNextResume = false;
  Completer<void>? heldSend;
  Completer<void>? heldLanguageChange;

  AssistantSession session(String uid) => AssistantSession(
    AssistantHistoryApi(
      uid,
      transport: HttpPaymentApi(
        baseUrl: 'https://localhost',
        token: () async => uid,
        client: client,
      ),
    ),
  );

  http.Response response(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> page(String? id) => {
    'conversation': rooms[id],
    'turns': turns[id] ?? [],
    'language': rooms[id]?['language'] ?? defaultLanguage,
    'before': null,
  };

  Future<http.Response> handle(http.Request request) async {
    final parts = request.url.pathSegments.skip(2).toList();
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (parts.isEmpty) {
      if (failNextResume) {
        failNextResume = false;
        return response({'error': 'SERVICE_UNAVAILABLE'}, 503);
      }
      return response(page(active));
    }
    final id = parts.first;
    if (id == 'list') {
      final query = body['query'] as String? ?? '';
      return response({
        'records': rooms.values
            .where(
              (row) =>
                  row['archived'] == body['archived'] &&
                  (row['title'] as String).toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList(),
        'nextCursor': null,
      });
    }
    if (id == 'new' || id == 'preferences') {
      if (id == 'preferences') {
        await heldLanguageChange?.future;
        if (failLanguageChange) {
          return response({'error': 'SERVICE_UNAVAILABLE'}, 503);
        }
      }
      if (id == 'new') active = null;
      defaultLanguage = body['language'] as String;
      return response({'saved': true});
    }
    final action = parts.length == 2 ? parts.last : '';
    if (action == 'send') {
      sentBodies.add(body);
      final requestId = body['requestId'] as String;
      submissions.add(requestId);
      final row = rooms.putIfAbsent(
        id,
        () => {
          'id': id,
          'title': 'Fitting fees',
          'archived': false,
          'updatedAt': 1794800000000,
          'language': body['language'],
        },
      );
      final entries = turns.putIfAbsent(id, () => []);
      final entry = entries.firstWhere(
        (entry) => entry['id'] == requestId,
        orElse: () {
          final next = {
            'id': requestId,
            'question': body['message'],
            'sequence': entries.length + 1,
            'status': 'complete',
            'reply': {
              'answer': 'Saved reply ${entries.length + 1}',
              'mode': 'Guide',
              'handoff': false,
              'sources': [],
            },
          };
          entries.add(next);
          return next;
        },
      );
      active = id;
      // A transport failure after the server commits must not duplicate the turn.
      if (failNextSend) {
        failNextSend = false;
        return response({'error': 'SERVICE_UNAVAILABLE'}, 503);
      }
      await heldSend?.future;
      return response({'conversation': row, 'turn': entry});
    }
    final row = rooms[id];
    if (row == null) {
      return response({'error': 'ASSISTANT_CONVERSATION_MISSING'}, 404);
    }
    if (action == 'open' && row['archived'] == false) active = id;
    if (action == 'update') {
      if (body.containsKey('language')) {
        await heldLanguageChange?.future;
        if (failLanguageChange) {
          return response({'error': 'SERVICE_UNAVAILABLE'}, 503);
        }
      }
      row.addAll(body);
      if (row['archived'] == true && active == id) active = null;
      return response(row);
    }
    if (action == 'delete') {
      if (active == id) active = null;
      rooms.remove(id);
      turns.remove(id);
      return response({'deleted': true});
    }
    return response(page(id));
  }
}

Future<void> mount(
  WidgetTester t,
  AssistantSession session, {
  double textScale = 1,
  Locale? locale,
  FakeAssistant? assistant,
  Future<void> Function(String)? onContact,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openLuvlyAssistant(
                context,
                session: session,
                api: assistant ?? (FakeAssistant()..enabled = false),
                onContact: onContact,
              ),
              child: const Text('Open chat'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> open(WidgetTester t) => tap(t, find.text('Open chat'));
Future<void> history(WidgetTester t) =>
    tap(t, find.byTooltip('Conversation history'));

Future<void> typeQuestion(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'reopen and restart, retain drafts, and retry with the same request',
    (t) async {
      final server = ChatFixture()..failNextSend = true;
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(t, session);
      await open(t);
      expect(find.text('How much is a fitting?'), findsOneWidget);
      await typeQuestion(t, 'How much is the fitting fee?');
      await tap(t, find.byTooltip('Send question'));
      expect(find.text('Retry message'), findsOneWidget);
      await tap(t, find.text('Retry message'));
      expect(server.submissions.length, 2);
      expect(server.submissions.toSet().length, 1);
      expect(find.text('Saved reply 1'), findsOneWidget);
      expect(
        find.byKey(const Key('assistant-question-starters')),
        findsNothing,
      );
      await chatOption(t, 'Bahasa Melayu');
      await typeQuestion(t, 'An unsent draft');
      await tap(t, find.byTooltip('Tutup pembantu'));
      await open(t);
      expect(find.text('Saved reply 1'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'An unsent draft',
      );
      await tap(t, find.byTooltip('Tutup pembantu'));

      session.dispose();
      expect(session.drafts, isEmpty);
      expect(session.submissions, isEmpty);
      final restarted = server.session('customer');
      addTearDown(restarted.dispose);
      await mount(t, restarted);
      await open(t);
      expect(find.text('Saved reply 1'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tap(t, find.byTooltip('Pilihan perbualan'));
      expect(find.text('✓ Bahasa Melayu'), findsOneWidget);
      await t.tapAt(const Offset(12, 460));
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'small screen history supports independent sessions and lifecycle actions',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(330, 640);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final server = ChatFixture();
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(t, session);
      await open(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      await t.pumpAndSettle();
      expect(t.getBottomRight(find.byType(TextField)).dy, lessThan(380));
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await typeQuestion(t, 'Chat one question');
      await tap(t, find.byTooltip('Send question'));
      final first = server.active;
      await chatOption(t, 'New conversation');
      expect(server.active, isNull);
      expect(server.rooms.length, 1);
      await typeQuestion(t, 'Chat two question');
      await tap(t, find.byTooltip('Send question'));
      expect(server.active, isNot(first));
      expect(find.text('Chat one question'), findsNothing);
      await history(t);
      expect(find.text('Your conversations'), findsOneWidget);

      await tap(t, find.byTooltip('Options for Fitting fees').first);
      await tap(t, find.text('Rename'));
      await t.enterText(
        find.widgetWithText(TextField, 'Conversation title'),
        'First fitting',
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Save title'));
      await typeQuestion(t, 'First fitting');
      await t.pumpAndSettle(const Duration(milliseconds: 350));
      expect(find.text('Fitting fees'), findsNothing);
      await tap(t, find.byTooltip('Options for First fitting'));
      await tap(t, find.text('Archive'));
      expect(find.text('No matching conversations.'), findsOneWidget);
      await tap(t, find.text('Archived'));
      await tap(t, find.text('First fitting').last);
      expect(find.text('Chat one question'), findsOneWidget);
      expect(find.text('Chat two question'), findsNothing);
      expect(find.byTooltip('Send question'), findsNothing);
      await tap(t, find.text('Restore to continue chatting'));
      expect(find.byTooltip('Send question'), findsOneWidget);
      await history(t);
      await tap(t, find.byTooltip('Options for First fitting'));
      await tap(t, find.text('Delete'));
      await tap(t, find.text('Delete permanently'));
      expect(server.turns[first], isNull);
      await tap(t, find.byTooltip('Back').first);
      expect(
        find.text('This conversation is no longer available.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'closing while a reply is in flight leaves saved history available',
    (t) async {
      final server = ChatFixture()..heldSend = Completer<void>();
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(t, session);
      await open(t);
      await typeQuestion(t, 'Can I book a fitting?');
      await t.tap(find.byTooltip('Send question'));
      await t.pump();
      expect(server.submissions, hasLength(1));
      await tap(t, find.byTooltip('Close assistant'));
      await open(t);
      expect(find.text('Saved reply 1'), findsOneWidget);
      server.heldSend!.complete();
      await t.pumpAndSettle();
      expect(server.submissions, hasLength(1));
    },
  );

  testWidgets(
    'history error keeps the offline guide available and resume can retry',
    (t) async {
      final server = ChatFixture()..failNextResume = true;
      final session = server.session('customer');
      addTearDown(session.dispose);
      await mount(t, session);
      await open(t);
      expect(find.text('Couldn’t load your saved chat.'), findsOneWidget);
      expect(find.text('Use offline help guide'), findsOneWidget);
      await tap(t, find.text('Retry'));
      expect(
        find.byKey(const Key('assistant-question-starters')),
        findsOneWidget,
      );
    },
  );
}
