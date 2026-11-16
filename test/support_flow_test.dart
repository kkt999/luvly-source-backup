import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/support/support_screens.dart';

class MemorySupport implements SupportRepository {
  SupportCase? ticket;
  final messages = <SupportReply>[];
  final changes = StreamController<void>.broadcast();
  bool fail = false;
  @override
  Stream<SupportCase?> watch(String id) async* {
    yield ticket;
    await for (final _ in changes.stream) {
      yield ticket;
    }
  }

  @override
  Stream<List<SupportCase>> cases({String? uid}) async* {
    yield [if (ticket != null && (uid == null || ticket!.uid == uid)) ticket!];
  }

  @override
  Stream<List<SupportReply>> replies(String id) async* {
    yield List.of(messages);
    await for (final _ in changes.stream) {
      yield List.of(messages);
    }
  }

  @override
  Future<String> create({
    required String uid,
    required String name,
    required String subject,
    required String category,
    required String body,
  }) async {
    ticket = SupportCase('a', {
      'uid': uid,
      'name': name,
      'subject': subject,
      'category': category,
      'status': 'Open',
      'revision': 1,
    });
    await reply('a', actor: uid, name: name, staff: false, body: body);
    return 'a';
  }

  @override
  Future<void> reply(
    String id, {
    required String actor,
    required String name,
    required bool staff,
    required String body,
  }) async {
    if (fail) throw StateError('Please retry');
    messages.add(
      SupportReply('${messages.length}', {
        'body': body,
        'senderName': name,
        'senderRole': staff ? 'staff' : 'bride',
      }),
    );
    ticket = SupportCase('a', {
      ...ticket!.data,
      'status': staff ? 'In Progress' : 'Open',
    });
    changes.add(null);
  }

  @override
  Future<void> close(SupportCase t, String actor) async {
    ticket = SupportCase('a', {...t.data, 'status': 'Closed'});
    changes.add(null);
  }
}

void main() {
  test('support input validation', () {
    expect(supportTextError('   ', 1, 2000), isNotNull);
    expect(supportTextError('a' * 2001, 1, 2000), isNotNull);
    expect(supportTextError('Hello\u0000', 1, 2000), isNotNull);
    expect(supportTextError('请问可以试婚纱吗？', 1, 2000), isNull);
  });
  testWidgets('create, team reply, failed draft retained, close history', (
    t,
  ) async {
    final repo = MemorySupport();
    addTearDown(repo.changes.close);
    await t.pumpWidget(
      SupportScope(
        repository: repo,
        child: const MaterialApp(
          home: NewSupportTicket(uid: 'a', name: 'Jane'),
        ),
      ),
    );
    await t.enterText(find.byType(TextFormField).at(0), 'Fitting question');
    await t.enterText(
      find.byType(TextFormField).at(1),
      'May I try this dress?',
    );
    await t.ensureVisible(find.text('Send question'));
    await t.tap(find.text('Send question'));
    await t.pumpAndSettle();
    expect(find.text('May I try this dress?'), findsOneWidget);
    await repo.reply(
      'a',
      actor: 'staff',
      name: 'John',
      staff: true,
      body: 'Yes, please book a fitting.',
    );
    await t.pumpAndSettle();
    expect(find.text('John · Luvly team'), findsOneWidget);
    repo.fail = true;
    await t.enterText(find.byType(TextField), 'Thank you');
    await t.tap(find.byTooltip('Send reply'));
    await t.pumpAndSettle();
    expect(find.text('Please retry'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Thank you',
    );
    repo.fail = false;
    await t.tap(find.byTooltip('Send reply'));
    await t.pumpAndSettle();
    expect(repo.messages.last.body, 'Thank you');
    await t.tap(find.text('Close conversation'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Close conversation'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('This conversation is closed. Your history is saved.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
