import 'package:cloud_firestore/cloud_firestore.dart';

class ShortlistSnapshot {
  const ShortlistSnapshot(this.ids, {this.fromCache = false});
  final List<String> ids;
  final bool fromCache;
}

abstract interface class ShortlistRepository {
  Stream<ShortlistSnapshot> watch(String uid);
  Future<void> setSaved(String uid, String dressId, bool saved);
}

class FirebaseShortlistRepository implements ShortlistRepository {
  FirebaseShortlistRepository({FirebaseFirestore? firestore}) : _db = firestore;
  final FirebaseFirestore? _db;
  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> collection(String uid) =>
      db.collection('brides').doc(uid).collection('shortlist');
  @override
  Stream<ShortlistSnapshot> watch(String uid) async* {
    await for (final snapshot in collection(
      uid,
    ).snapshots(includeMetadataChanges: true)) {
      if (snapshot.metadata.hasPendingWrites) continue;
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final left =
              (a.data()['savedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final right =
              (b.data()['savedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final byDate = right.compareTo(left);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
      yield ShortlistSnapshot(
        docs.map((doc) => doc.id).toList(growable: false),
        fromCache: snapshot.metadata.isFromCache,
      );
    }
  }

  @override
  Future<void> setSaved(String uid, String dressId, bool saved) async {
    if (uid.isEmpty ||
        dressId.isEmpty ||
        dressId.contains('/') ||
        dressId.length > 128) {
      throw ArgumentError('Invalid shortlist reference');
    }
    final ref = collection(uid).doc(dressId);
    // Server transactions prevent queued offline writes and duplicate favourites.
    await db.runTransaction(
      (tx) async {
        final existing = await tx.get(ref);
        if (!saved) {
          if (existing.exists) tx.delete(ref);
          return;
        }
        final gown = await tx.get(db.collection('dresses').doc(dressId));
        if (!gown.exists || gown.data()?['published'] != true) {
          throw StateError('This gown is no longer listed.');
        }
        if (!existing.exists) {
          tx.set(ref, {
            'dressId': dressId,
            'savedAt': FieldValue.serverTimestamp(),
          });
        }
      },
      timeout: const Duration(seconds: 12),
      maxAttempts: 2,
    );
  }
}
