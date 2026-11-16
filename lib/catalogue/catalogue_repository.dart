import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'dress_photo_data.dart';
import 'ar_models.dart';

const dressCategories = ['A-Line', 'Ball Gown', 'Mermaid', 'Sheath'];
const dressAvailability = ['Available', 'Unavailable'];
const dressColours = [
  'White',
  'Ivory',
  'Off-white',
  'Champagne',
  'Blush',
  'Nude',
  'Silver',
  'Gold',
  'Red',
  'Blue',
  'Black',
  'Multicolour',
];
const dressSizes = [
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  '2XL',
  '3XL',
  '4XL',
  '5XL',
  'Made to measure',
];

String? validateDressText(String value, String label, int min, int max) {
  final text = value.trim();
  if (text.length < min || text.length > max) {
    return '$label must contain $min–$max characters.';
  }
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(text) ||
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(text)) {
    return 'Enter a readable $label, not only numbers or symbols.';
  }
  return null;
}

bool validDressSizes(String value) {
  final selected = value.split(', ');
  return selected.isNotEmpty &&
      selected.every(dressSizes.contains) &&
      selected.toSet().length == selected.length &&
      (!selected.contains('Made to measure') || selected.length == 1);
}

int? parsePriceCents(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return cents >= 1 && cents <= 100000000 ? cents : null;
}

bool validPhotoUrl(String value) {
  final uri = Uri.tryParse(value);
  return value.length <= 2000 &&
      !RegExp(r'\s').hasMatch(value) &&
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.contains('.') &&
      uri.userInfo.isEmpty;
}

class CatalogueDress {
  const CatalogueDress({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.colour,
    required this.sizes,
    required this.priceCents,
    required this.imageUrl,
    this.availability = 'Available',
    this.published = false,
    this.revision = 0,
    this.photoRevision = 0,
    this.arModelId = '',
    this.productDetails = const {},
  });
  final String id,
      name,
      category,
      description,
      colour,
      sizes,
      imageUrl,
      availability;
  final int priceCents, revision, photoRevision;
  final bool published;
  final String arModelId;
  final Map<String, String> productDetails;
  String get priceLabel => 'RM ${(priceCents / 100).toStringAsFixed(2)}';

  String? get validationError {
    if (productDetails.entries.any(
      (e) =>
          !const [
            'neckline',
            'fabricAppearance',
            'train',
            'features',
          ].contains(e.key) ||
          e.value.trim() != e.value ||
          e.value.isEmpty ||
          e.value.length > (e.key == 'features' ? 600 : 160) ||
          RegExp(r'[\x00-\x1F\x7F]').hasMatch(e.value),
    )) {
      return 'Enter valid product details.';
    }
    if (arModelId.isNotEmpty && resolveCatalogueArDress(arModelId) == null) {
      return 'Select a supported AR model or No AR model.';
    }
    if (name != name.trim() || description != description.trim()) {
      return 'Remove surrounding whitespace from the dress details.';
    }
    final nameError = validateDressText(name, 'dress name', 3, 100);
    if (nameError != null) return nameError;
    final descriptionError = validateDressText(
      description,
      'description',
      20,
      3000,
    );
    if (descriptionError != null) return descriptionError;
    if (!dressColours.contains(colour)) return 'Select a dress colour.';
    if (!validDressSizes(sizes)) {
      return 'Select available sizes or Made to measure.';
    }
    if (!dressCategories.contains(category) ||
        !dressAvailability.contains(availability)) {
      return 'Choose a valid style and availability.';
    }
    if (priceCents < 1 || priceCents > 100000000) {
      return 'Enter a price greater than RM 0.';
    }
    if (imageUrl.isNotEmpty && !validPhotoUrl(imageUrl)) {
      return 'Enter a valid HTTPS photo link.';
    }
    if (photoRevision < 0 ||
        photoRevision > revision + 1 ||
        (photoRevision > 0 && imageUrl.isNotEmpty)) {
      return 'Invalid photo reference.';
    }
    if (published && imageUrl.isEmpty && photoRevision == 0) {
      return 'Add a photo before publishing.';
    }
    return null;
  }

  Map<String, dynamic> toFields() => {
    'name': name,
    'category': category,
    'description': description,
    if (productDetails.isNotEmpty) 'productDetails': productDetails,
    'colour': colour,
    'sizes': sizes,
    'priceCents': priceCents,
    'imageUrl': imageUrl,
    if (arModelId.isNotEmpty) 'arModelId': arModelId,
    'photoRevision': photoRevision,
    'availability': availability,
    'published': published,
  };

  factory CatalogueDress.fromFields(String id, Map<String, dynamic> d) =>
      CatalogueDress(
        id: id,
        name: d['name'] as String,
        category: d['category'] as String,
        description: d['description'] as String,
        productDetails: Map<String, String>.from(
          d['productDetails'] as Map? ?? const {},
        ),
        colour: d['colour'] as String,
        sizes: d['sizes'] as String,
        priceCents: d['priceCents'] as int,
        imageUrl: d['imageUrl'] as String,
        availability: d['availability'] as String,
        published: d['published'] as bool,
        revision: d['revision'] as int,
        photoRevision: (d['photoRevision'] as int?) ?? 0,
        arModelId: (d['arModelId'] as String?) ?? '',
      );
}

class CatalogueSnapshot {
  const CatalogueSnapshot(this.dresses, {this.fromCache = false});
  final List<CatalogueDress> dresses;
  final bool fromCache;
}

abstract interface class CatalogueRepository {
  Stream<CatalogueSnapshot> watch({required bool inventory});
  Future<void> save(
    CatalogueDress dress, {
    required String actorUid,
    DressPhotoData? photo,
  });
  Stream<DressPhotoData?> watchPhoto(CatalogueDress dress);
  String newId();
}

class FirebaseCatalogueRepository implements CatalogueRepository {
  FirebaseCatalogueRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;
  final FirebaseFirestore? _firestore;
  FirebaseFirestore get db => _firestore ?? FirebaseFirestore.instance;
  @override
  String newId() => db.collection('dresses').doc().id;

  @override
  Stream<CatalogueSnapshot> watch({required bool inventory}) async* {
    Query<Map<String, dynamic>> query = db.collection('dresses');
    // Rules are not filters: the bride query must constrain publication itself.
    if (!inventory) query = query.where('published', isEqualTo: true);
    await for (final snapshot in query.snapshots(
      includeMetadataChanges: true,
    )) {
      // Never present a pending local write as a confirmed catalogue change.
      if (snapshot.metadata.hasPendingWrites) continue;
      final dresses =
          snapshot.docs
              .map((d) => CatalogueDress.fromFields(d.id, d.data()))
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      yield CatalogueSnapshot(
        dresses,
        fromCache: snapshot.metadata.isFromCache,
      );
    }
  }

  @override
  Stream<DressPhotoData?> watchPhoto(CatalogueDress dress) async* {
    await for (final snapshot
        in db
            .collection('dressPhotos')
            .doc(dress.id)
            .snapshots(includeMetadataChanges: true)) {
      // Never display a private photo solely on the authority of an offline cache.
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        yield null;
        continue;
      }
      final fields = snapshot.data();
      if (fields == null || fields['revision'] != dress.photoRevision) {
        yield null;
      } else {
        yield DressPhotoData.fromFields(fields);
      }
    }
  }

  @override
  Future<void> save(
    CatalogueDress dress, {
    required String actorUid,
    DressPhotoData? photo,
  }) async {
    final error = dress.validationError;
    if (error != null) throw StateError(error);
    final ref = db.collection('dresses').doc(dress.id);
    // Server transactions fail offline and prevent silently overwriting a newer edit.
    await db.runTransaction((tx) async {
      final current = await tx.get(ref);
      if (current.exists
          ? current.data()!['revision'] != dress.revision
          : dress.revision != 0) {
        throw StateError(
          'This dress changed elsewhere. Close this form and reopen the latest version.',
        );
      }
      final oldPhotoRevision = (current.data()?['photoRevision'] as int?) ?? 0;
      if (photo != null
          ? dress.photoRevision != dress.revision + 1
          : dress.photoRevision != 0 &&
                dress.photoRevision != oldPhotoRevision) {
        throw StateError('Select the photo again before saving.');
      }
      final photoRef = db.collection('dressPhotos').doc(dress.id);
      if (photo != null) {
        tx.set(photoRef, {
          ...photo.toFields(),
          'revision': dress.photoRevision,
          'updatedBy': actorUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (oldPhotoRevision > 0 && dress.photoRevision == 0) {
        tx.delete(photoRef);
      }
      final fields = {
        ...dress.toFields(),
        'revision': dress.revision + 1,
        'updatedBy': actorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (current.exists) {
        if (dress.arModelId.isEmpty &&
            current.data()!.containsKey('arModelId')) {
          fields['arModelId'] = FieldValue.delete();
        }
        tx.update(ref, fields);
      } else {
        tx.set(ref, {
          ...fields,
          'createdBy': actorUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}

class CatalogueScope extends InheritedWidget {
  const CatalogueScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final CatalogueRepository repository;
  static CatalogueRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CatalogueScope>()!.repository;
  @override
  bool updateShouldNotify(CatalogueScope oldWidget) =>
      repository != oldWidget.repository;
}
