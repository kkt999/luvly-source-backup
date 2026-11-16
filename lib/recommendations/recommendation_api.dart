import 'dart:math';
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
  ) async => PreferenceRecord.parse(
    await _transport.request(
      '/v1/my-recommendation-profile',
      body: {
        'revision': old.revision,
        'requestId': requestId,
        'profile': next.toJson(),
      },
    ),
  );
  void close() {
    if (_owns) _transport.close();
  }
}
