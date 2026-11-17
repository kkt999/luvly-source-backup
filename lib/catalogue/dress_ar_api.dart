import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import '../payments/payment_api.dart';

const dressArEstimatedCredits = 30;

class DressArStatus {
  DressArStatus.fromJson(Map data)
    : configured = data['configured'] == true,
      credits =
          (data['estimateCredits'] as num?)?.toInt() ?? dressArEstimatedCredits,
      spent = data['credits'] as num?,
      state = data['state'] as String,
      progress = (data['progress'] as num?)?.toInt() ?? 0,
      error = data['error'] as String?,
      approved = data['approved'] == true,
      front = data['front'] as String,
      hasPreview = data['preview'] == true;

  final bool configured, approved, hasPreview;
  final int credits, progress;
  final num? spent;
  final String state, front;
  final String? error;
  bool get inProgress => ['preparing', 'submitting', 'running'].contains(state);
  bool get canGenerate =>
      configured &&
      (state == 'idle' ||
          state == 'failed' && error != 'TRIPO_UNSUPPORTED_MODEL');
}

class DressArApi {
  DressArApi(String uid, this.dressId, this.photoRevision)
    : _transport = HttpPaymentApi(
        token: () async {
          final user = FirebaseAuth.instance.currentUser;
          return user?.uid == uid ? user!.getIdToken() : null;
        },
      );

  final HttpPaymentApi _transport;
  final String dressId;
  final int photoRevision;

  String get _path =>
      '/v1/dresses/${Uri.encodeComponent(dressId)}/ar/$photoRevision';

  Future<DressArStatus> status() async => DressArStatus.fromJson(
    await _transport.businessRequest('$_path/status') as Map,
  );
  Future<DressArStatus> generate() async => DressArStatus.fromJson(
    await _transport.businessRequest(
          '$_path/generate',
          body: const {'confirmed': true},
        )
        as Map,
  );
  Future<DressArStatus> approve(bool enabled, String front) async =>
      DressArStatus.fromJson(
        await _transport.businessRequest(
              '$_path/approval',
              body: {'approved': enabled, 'front': front},
            )
            as Map,
      );
  Future<bool> available() async =>
      (await _transport.businessRequest('$_path/available')
          as Map)['available'] ==
      true;
  Future<Uint8List> model() => _transport.downloadBusinessFile(
    '$_path/model',
    types: const {'model/gltf-binary'},
    maxBytes: 12 * 1024 * 1024,
  );
  Future<Uint8List> preview() => _transport.downloadBusinessFile(
    '$_path/preview',
    types: const {'image/jpeg', 'image/png', 'image/webp'},
    maxBytes: 2 * 1024 * 1024,
  );
  void close() => _transport.close();
}

String dressArError(String? code) => switch (code) {
  'TRIPO_NOT_CONFIGURED' => 'Tripo is not configured on the Luvly server.',
  'TRIPO_INSUFFICIENT_CREDITS' => 'This Tripo account needs more credits.',
  'TRIPO_PHOTO_CHANGED' => 'The dress photo changed. Open the latest dress.',
  'TRIPO_PHOTO_REQUIRED' => 'Save an uploaded dress photo before generating.',
  'TRIPO_BUNDLED_MODEL_SELECTED' =>
    'Clear the selected AR model and save first.',
  'TRIPO_REJECTED' => 'Tripo rejected the request. Check the key and photo.',
  'TRIPO_UNSUPPORTED_MODEL' =>
    'The existing model could not be prepared. Check status to try preparing it again without using credits.',
  'TRIPO_TASK_FAILED' => 'Tripo could not generate a model from this photo.',
  'MANAGER_REQUIRED' => 'An active manager account is required.',
  'NOT_FOUND' => 'The portal backend has not been updated for Tripo.',
  _ => 'Could not reach the 3D service. Check status again.',
};
