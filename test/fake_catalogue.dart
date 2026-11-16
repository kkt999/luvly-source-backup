import 'dart:async';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';

class FakeCatalogue implements CatalogueRepository {
  final records = <String, CatalogueDress>{};
  final photos = <String, DressPhotoData>{};
  final changes = StreamController<void>.broadcast(sync: true);
  Object? saveError;
  Completer<void>? saveWait;
  bool readError = false;
  int saves = 0, ids = 0;
  @override
  String newId() => 'dress-${++ids}';
  @override
  Stream<CatalogueSnapshot> watch({required bool inventory}) async* {
    CatalogueSnapshot snapshot() => CatalogueSnapshot(
      records.values.where((d) => inventory || d.published).toList(),
    );
    if (readError) throw StateError('Synthetic connection error');
    yield snapshot();
    await for (final _ in changes.stream) {
      yield snapshot();
    }
  }

  @override
  Stream<DressPhotoData?> watchPhoto(CatalogueDress dress) async* {
    yield photos[dress.id];
    await for (final _ in changes.stream) {
      yield photos[dress.id];
    }
  }

  @override
  Future<void> save(
    CatalogueDress dress, {
    required String actorUid,
    DressPhotoData? photo,
  }) async {
    saves++;
    if (saveWait != null) await saveWait!.future;
    if (saveError != null) throw saveError!;
    if (dress.validationError != null) throw StateError(dress.validationError!);
    if ((records[dress.id]?.revision ?? 0) != dress.revision) {
      throw StateError('This dress changed elsewhere.');
    }
    if (photo != null) photos[dress.id] = photo;
    if (dress.photoRevision == 0) photos.remove(dress.id);
    records[dress.id] = CatalogueDress.fromFields(dress.id, {
      ...dress.toFields(),
      'revision': dress.revision + 1,
    });
    changes.add(null);
  }
}

CatalogueDress sampleDress({
  String id = 'dress-1',
  bool published = true,
  int revision = 1,
  String name = 'Test Lace Dress',
}) => CatalogueDress(
  id: id,
  name: name,
  category: 'A-Line',
  description: 'A lace gown for a test fitting.',
  colour: 'Ivory',
  sizes: 'S, M',
  priceCents: 125050,
  imageUrl: 'https://example.com/dress.jpg',
  published: published,
  revision: revision,
);
