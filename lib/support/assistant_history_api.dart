import 'package:firebase_auth/firebase_auth.dart';
import '../payments/payment_api.dart';
import 'assistant_api.dart';

class AssistantConversation {
  const AssistantConversation({
    required this.id,
    required this.title,
    required this.language,
    required this.updatedAt,
    this.preview,
    this.archived = false,
    this.deleting = false,
  });

  final String id, title, language;
  final String? preview;
  final DateTime updatedAt;
  final bool archived, deleting;

  factory AssistantConversation.fromJson(Map data) => AssistantConversation(
    id: data['id'] as String,
    title: data['title'] as String,
    language: data['language'] as String,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    preview: data['preview'] as String?,
    archived: data['archived'] == true,
    deleting: data['deleting'] == true,
  );
}

class AssistantTurn {
  const AssistantTurn({
    required this.question,
    required this.id,
    this.sequence = 0,
    this.status = 'generating',
    this.reply,
  });
  final String question, id, status;
  final int sequence;
  final AssistantReply? reply;

  factory AssistantTurn.fromJson(Map data) => AssistantTurn(
    question: data['question'] as String,
    id: data['id'] as String,
    sequence: data['sequence'] as int,
    status: data['status'] as String,
    reply: data['reply'] == null
        ? null
        : AssistantReply.fromJson(Map<String, dynamic>.from(data['reply'])),
  );
}

class AssistantChatPage {
  const AssistantChatPage({
    this.conversation,
    this.turns = const [],
    this.before,
    this.language = 'auto',
  });
  final AssistantConversation? conversation;
  final List<AssistantTurn> turns;
  final int? before;
  final String language;

  factory AssistantChatPage.fromJson(Map data) => AssistantChatPage(
    conversation: data['conversation'] == null
        ? null
        : AssistantConversation.fromJson(data['conversation']),
    turns: [
      for (final turn in data['turns'] as List) AssistantTurn.fromJson(turn),
    ],
    before: data['before'] as int?,
    language: data['language'] as String,
  );
}

typedef AssistantHistoryPage = ({
  List<AssistantConversation> records,
  String? nextCursor,
});
typedef AssistantSendResult = ({
  AssistantConversation? conversation,
  AssistantTurn? turn,
  AssistantReply? privacy,
});

class AssistantHistoryApi {
  AssistantHistoryApi(String uid, {HttpPaymentApi? transport})
    : _transport =
          transport ??
          HttpPaymentApi(
            token: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user?.uid != uid) return null;
              return user!.getIdToken();
            },
          );
  final HttpPaymentApi _transport;
  static const _base = '/v1/assistant-conversations';

  Future<AssistantChatPage> resume() async =>
      AssistantChatPage.fromJson(await _transport.businessRequest(_base));

  Future<AssistantHistoryPage> list({
    required bool archived,
    String query = '',
    String? cursor,
  }) async {
    final data =
        await _transport.businessRequest(
              '$_base/list',
              body: {
                'archived': archived,
                if (query.isNotEmpty) 'query': query,
                'cursor': ?cursor,
              },
            )
            as Map;
    return (
      records: [
        for (final row in data['records'] as List)
          AssistantConversation.fromJson(row),
      ],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<AssistantChatPage> open(String id) async => AssistantChatPage.fromJson(
    await _transport.businessRequest('$_base/$id/open', body: const {}),
  );

  Future<AssistantChatPage> read(String id, {int? before}) async =>
      AssistantChatPage.fromJson(
        await _transport.businessRequest(
          '$_base/$id${before == null ? '' : '?before=$before'}',
        ),
      );

  Future<void> newChat(String language) async {
    await _transport.businessRequest(
      '$_base/new',
      body: {'language': language},
    );
  }

  Future<void> setLanguage(String? id, String language) async {
    await _transport.businessRequest(
      id == null ? '$_base/preferences' : '$_base/$id/update',
      body: {'language': language},
    );
  }

  Future<void> rename(String id, String title) async {
    await _transport.businessRequest(
      '$_base/$id/update',
      body: {'title': title},
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    await _transport.businessRequest(
      '$_base/$id/update',
      body: {'archived': archived},
    );
  }

  Future<void> delete(String id) async {
    await _transport.businessRequest('$_base/$id/delete', body: const {});
  }

  Future<AssistantSendResult> send(
    String id, {
    required String requestId,
    required String language,
    required bool ai,
    required bool create,
    String? question,
  }) async {
    final data =
        await _transport.businessRequest(
              '$_base/$id/send',
              body: {
                'requestId': requestId,
                'language': language,
                'mode': ai ? 'AI' : 'Guide',
                if (create) 'create': true,
                if (ai) 'consentVersion': 3,
                'message': ?question,
              },
            )
            as Map;
    return (
      conversation: data['conversation'] == null
          ? null
          : AssistantConversation.fromJson(data['conversation']),
      turn: data['turn'] == null ? null : AssistantTurn.fromJson(data['turn']),
      privacy: data['privacy'] == null
          ? null
          : AssistantReply.fromJson(Map<String, dynamic>.from(data['privacy'])),
    );
  }

  void close() => _transport.close();
}

// Kept by the signed-in customer shell. Unsent text never leaves memory.
class AssistantSession {
  AssistantSession(this.history);
  final AssistantHistoryApi history;
  final drafts = <String, String>{};
  final submissions = <String, AssistantTurn>{};
  Future<void>? _savingLanguage;
  String? newConversationId;
  bool disposed = false;
  int historyRevision = 0;
  String draftKey(String? conversationId) => conversationId ?? '';

  Future<AssistantChatPage> resume() async {
    try {
      await _savingLanguage;
    } catch (_) {
      // Restore the confirmed preference if the previous save failed.
    }
    return history.resume();
  }

  Future<void> saveLanguage(String? id, String language) async {
    final update = history.setLanguage(id, language);
    _savingLanguage = update;
    try {
      await update;
    } finally {
      if (identical(_savingLanguage, update)) _savingLanguage = null;
    }
  }

  void rememberDraft(String? id, String text) {
    final key = draftKey(id);
    if (text.isEmpty) {
      drafts.remove(key);
    } else {
      drafts[key] = text;
    }
  }

  void forget(String id) {
    drafts.remove(id);
    submissions.remove(id);
    if (newConversationId == id) newConversationId = null;
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    drafts.clear();
    submissions.clear();
    newConversationId = null;
    history.close();
  }
}
