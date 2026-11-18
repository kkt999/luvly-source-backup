import 'dart:math';
import 'dart:async';
import 'dart:convert';
import '../workspace/workspace_api.dart';
import 'recommendation_engine.dart';

class PreferenceRecord {
  const PreferenceRecord(this.revision, this.preferences);
  final int revision;
  final BridalPreferences preferences;
  factory PreferenceRecord.parse(Map<String, dynamic> row) {
    if (row['revision'] is! int || row['revision'] < 0) {
      throw const FormatException('Invalid profile revision');
    }
    return PreferenceRecord(
      row['revision'],
      BridalPreferences.fromJson(Map<String, dynamic>.from(row['profile'])),
    );
  }
}

/// Account-scoped invalidation only. No body measurements are retained here.
class RecommendationProfileChanges {
  static final _changes =
      StreamController<({String uid, int revision})>.broadcast(sync: true);
  static Stream<({String uid, int revision})> get changes => _changes.stream;
  static void saved(String uid, int revision) =>
      _changes.add((uid: uid, revision: revision));
}

class RecommendationApi {
  RecommendationApi({WorkspaceApi? transport})
    : _transport = transport ?? WorkspaceApi(),
      _owns = transport == null;
  final WorkspaceApi _transport;
  final bool _owns;
  Future<PreferenceRecord> load() async => PreferenceRecord.parse(
    await _transport.request('/v1/my-recommendation-profile'),
  );
  String requestId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<PreferenceRecord> save(
    PreferenceRecord old,
    BridalPreferences next,
    String requestId,
  ) async {
    final saved = PreferenceRecord.parse(
      await _transport.request(
        '/v1/my-recommendation-profile',
        body: {
          'revision': old.revision,
          'requestId': requestId,
          'profile': next.toJson(),
        },
      ),
    );
    // An older server must not report a successful provenance save while
    // dropping the new fields. Keep the returned revision for a safe retry.
    if (next.measurementProvenance.fields.isNotEmpty &&
        jsonEncode(saved.preferences.measurementProvenance.toJson()) !=
            jsonEncode(next.measurementProvenance.toJson())) {
      throw PreferenceSaveFailure(saved);
    }
    return saved;
  }

  void close() {
    if (_owns) _transport.close();
  }
}

class PreferenceSaveFailure implements Exception {
  const PreferenceSaveFailure(this.saved);
  final PreferenceRecord saved;
}
