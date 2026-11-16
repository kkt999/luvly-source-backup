import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'dart:convert';
import '../workspace/workspace_api.dart';
import '../packages/package_api.dart' show packageRequestId;

const supportCategories = ['Appointments', 'Dresses & AR', 'Account', 'Other'];
String? supportTextError(String value, int min, int max) {
  final text = value.trim();
  if (text.length < min || text.length > max) {
    return 'Use $min–$max characters.';
  }
  if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(text)) {
    return 'Remove unsupported characters.';
  }
  return null;
}

class SupportCase {
  SupportCase(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get uid => data['uid'] as String;
  String get name => data['name'] as String;
  String get subject => data['subject'] as String;
  String get category => data['category'] as String;
  String get status => data['status'] as String;
  int get revision => data['revision'] as int;
  String? get lastMessageId {
    final value = data['lastMessageId'];
    return value is String && value.isNotEmpty && !value.contains('/')
        ? value
        : null;
  }
}

class SupportReply {
  SupportReply(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get body => data['body'] as String;
  String get sender => data['senderName'] as String;
  String get role => data['senderRole'] as String;
  DateTime? get sentAt => (data['sentAt'] as Timestamp?)?.toDate();
}

abstract class SupportRepository {
  Stream<List<SupportCase>> cases({String? uid});
  Stream<List<SupportReply>> replies(String id);
  Stream<SupportCase?> watch(String id);
  Future<String> create({
    required String uid,
    required String name,
    required String subject,
    required String category,
    required String body,
  });
  Future<void> reply(
    String id, {
    required String actor,
    required String name,
    required bool staff,
    required String body,
  });
  Future<void> close(SupportCase ticket, String actor);
}

abstract interface class SupportPreviewRepository {
  Future<String?> latestMessagePreview(SupportCase ticket);
}

class FirebaseSupportRepository
    implements SupportRepository, SupportPreviewRepository {
  FirebaseSupportRepository({FirebaseFirestore? database, WorkspaceApi? api})
    : _database = database,
      _api = api;
  final FirebaseFirestore? _database;
  final WorkspaceApi? _api;
  // Reuse a request after an uncertain response, including a scope rebuild.
  // A confirmed operation is removed, so intentional later replies remain new.
  static final _pending = <String, String>{};
  Future<Map<String, dynamic>> send(
    String path,
    String actor,
    Map<String, dynamic> body,
  ) async {
    final key = jsonEncode([actor, path, body]);
    if (_pending.length > 50) _pending.remove(_pending.keys.first);
    final requestId = _pending.putIfAbsent(key, packageRequestId),
        api = _api ?? WorkspaceApi();
    try {
      final result = await api.request(
        path,
        body: {...body, 'requestId': requestId},
      );
      _pending.remove(key);
      return result;
    } finally {
      if (_api == null) api.close();
    }
  }

  FirebaseFirestore get db => _database ?? FirebaseFirestore.instance;
  @override
  Stream<List<SupportCase>> cases({String? uid}) async* {
    Query<Map<String, dynamic>> q = db.collection('supportTickets');
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    yield* q.snapshots().map((s) {
      final result = s.docs.map((d) => SupportCase(d.id, d.data())).toList();
      result.sort(
        (a, b) =>
            ((b.data['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo(
                  (a.data['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                      0,
                ),
      );
      return result;
    });
  }

  @override
  Stream<SupportCase?> watch(String id) async* {
    yield* db
        .collection('supportTickets')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? SupportCase(d.id, d.data()!) : null);
  }

  @override
  Future<String?> latestMessagePreview(SupportCase ticket) async {
    final messageId = ticket.lastMessageId;
    if (messageId == null) return null;
    final message =
        (await db
                .collection('supportTickets')
                .doc(ticket.id)
                .collection('messages')
                .doc(messageId)
                .get(const GetOptions(source: Source.server)))
            .data();
    final role = message?['senderRole'];
    final body = message?['body'];
    if ((role != 'staff' && role != 'bride') || body is! String) return null;
    final preview = body.trim();
    return preview.isEmpty ? null : preview;
  }

  @override
  Stream<List<SupportReply>> replies(String id) async* {
    yield* db
        .collection('supportTickets')
        .doc(id)
        .collection('messages')
        .orderBy('sentAt')
        .limitToLast(100)
        .snapshots()
        .map((s) => s.docs.map((d) => SupportReply(d.id, d.data())).toList());
  }

  @override
  Future<String> create({
    required String uid,
    required String name,
    required String subject,
    required String category,
    required String body,
  }) async {
    if (supportTextError(subject, 3, 120) != null ||
        supportTextError(body, 1, 2000) != null ||
        !supportCategories.contains(category)) {
      throw StateError('Check the subject and message.');
    }
    final result = await send('/v1/support-messages', uid, {
      'action': 'Create',
      'subject': subject.trim(),
      'category': category,
      'body': body.trim(),
    });
    return result['id'] as String;
  }

  @override
  Future<void> reply(
    String id, {
    required String actor,
    required String name,
    required bool staff,
    required String body,
  }) async {
    if (supportTextError(body, 1, 2000) != null) {
      throw StateError('Write a message of 1–2,000 characters.');
    }
    await send('/v1/support-messages/$id', actor, {
      'action': 'Reply',
      'body': body.trim(),
    });
  }

  @override
  Future<void> close(SupportCase ticket, String actor) async {
    await send('/v1/support-messages/${ticket.id}', actor, {
      'action': 'Close',
      'revision': ticket.revision,
    });
  }
}

String supportError(Object e) => e is StateError
    ? e.message.toString()
    : 'Unable to reach support. Check your connection and retry. Your message has not been confirmed as sent.';

class SupportScope extends InheritedWidget {
  const SupportScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final SupportRepository repository;
  static SupportRepository? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<SupportScope>()?.repository;
  @override
  bool updateShouldNotify(SupportScope oldWidget) =>
      repository != oldWidget.repository;
}
