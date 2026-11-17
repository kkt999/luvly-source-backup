import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/admin/dress_ar_dialog.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/catalogue_widgets.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'fake_catalogue.dart';

Uint8List fixture() =>
    img.encodePng(img.Image(width: 200, height: 300, numChannels: 4));

void main() {
  test(
    'PNG becomes a small white-background JPEG and survives database serialization',
    () {
      final photo = compressDressPhoto(fixture());
      expect(photo.width, 200);
      expect(photo.height, 300);
      expect(photo.bytes.length, lessThanOrEqualTo(maxPhotoBytes));
      expect(
        photo.toFields()['data'].length,
        lessThanOrEqualTo(maxPhotoBase64Length),
      );
      expect(img.decodeJpg(photo.bytes)!.getPixel(0, 0).r, greaterThan(250));
      expect(DressPhotoData.fromFields(photo.toFields()).bytes, photo.bytes);
    },
  );
  test(
    'Large detailed photo is resized and compressed under the database limit',
    () {
      final random = Random(1);
      final image = img.Image(width: 1600, height: 1300);
      for (final pixel in image) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final photo = compressDressPhoto(img.encodeJpg(image, quality: 90));
      expect(photo.width, lessThanOrEqualTo(1200));
      expect(photo.height, lessThanOrEqualTo(1200));
      expect(photo.bytes.length, lessThanOrEqualTo(maxPhotoBytes));
    },
  );
  test('EXIF orientation is baked and metadata is removed', () {
    final original = img.Image(width: 100, height: 200);
    original.exif.imageIfd.orientation = 6;
    original.exif.gpsIfd.gpsLatitude = 3.14;
    final photo = compressDressPhoto(img.encodeJpg(original));
    expect(photo.width, 200);
    expect(photo.height, 100);
    final decoded = img.decodeJpg(photo.bytes)!;
    expect(decoded.exif.imageIfd.hasOrientation, isFalse);
    expect(decoded.exif.gpsIfd.gpsLatitude, isNull);
  });
  test('Empty, oversized, disguised, damaged and tiny images are rejected', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List(maxPhotoInputBytes + 1),
      Uint8List.fromList(utf8.encode('<svg>not a photo</svg>')),
      Uint8List.fromList([255, 216, 255, 0]),
      img.encodePng(img.Image(width: 10, height: 10)),
    ]) {
      expect(() => compressDressPhoto(bytes), throwsFormatException);
    }
  });
  test('Animated PNG and excessive pixel dimensions are rejected', () {
    final animation = img.Image(width: 100, height: 100);
    animation.addFrame(img.Image(width: 100, height: 100));
    expect(
      () => compressDressPhoto(img.encodePng(animation)),
      throwsFormatException,
    );
    // PNG header declares dimensions before decoding; no huge bitmap allocated.
    final bytes = fixture();
    ByteData.sublistView(bytes).setUint32(16, 7000);
    expect(() => compressDressPhoto(bytes), throwsFormatException);
  });
  test(
    'Picker input requires a supported extension and real image contents',
    () async {
      await expectLater(
        prepareDressPhoto(
          XFile.fromData(fixture(), path: 'dress.exe', name: 'dress.exe'),
        ),
        throwsFormatException,
      );
      await expectLater(
        prepareDressPhoto(
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            path: 'dress.jpg',
            name: 'dress.jpg',
          ),
        ),
        throwsFormatException,
      );
      final photo = await prepareDressPhoto(
        XFile.fromData(fixture(), path: 'dress.PNG', name: 'dress.PNG'),
      );
      expect(photo.width, 200);
    },
  );
  test('Stored photo validation rejects invalid data and dimensions', () {
    final valid = compressDressPhoto(fixture()).toFields();
    for (final change in <Map<String, dynamic>>[
      {'data': 'not base64'},
      {'data': 'A' * (maxPhotoBase64Length + 1)},
      {'mime': 'image/svg+xml'},
      {'width': 1201},
      {'height': 0},
      {'data': 'AAAA'},
    ]) {
      expect(
        () => DressPhotoData.fromFields({...valid, ...change}),
        throwsFormatException,
      );
    }
  });

  Future<void> editor(
    WidgetTester tester,
    FakeCatalogue repo,
    Future<XFile?> Function() pick, {
    bool creating = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: DressEditor(
          repository: repo,
          actorUid: 'manager',
          dress: creating ? null : sampleDress(),
          pickPhoto: pick,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(
    WidgetTester tester, [
    String button = 'Replace photo',
  ]) async {
    await tester.tap(find.text(button));
    await tester.pump(const Duration(milliseconds: 50));
    // Allow compute's real isolate to complete outside the widget-test fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Cancelling picker preserves the current photo without saving', (
    tester,
  ) async {
    final repo = FakeCatalogue();
    await editor(tester, repo, () async => null);
    await select(tester);
    expect(find.text('Replace photo'), findsOneWidget);
    expect(find.text('New photo · saved with the dress'), findsNothing);
    expect(repo.saves, 0);
    expect(find.text('Photo link (HTTPS)'), findsNothing);
  });
  testWidgets('Bad file keeps the old photo and displays an error', (
    tester,
  ) async {
    final repo = FakeCatalogue();
    await editor(
      tester,
      repo,
      () async =>
          XFile.fromData(Uint8List(3), path: 'bad.svg', name: 'bad.svg'),
    );
    await select(tester);
    expect(find.text('Choose a JPG or PNG photo.'), findsOneWidget);
    expect(find.text('Replace photo'), findsOneWidget);
    expect(repo.saves, 0);
  });
  testWidgets(
    'Selected photo survives failed save; retry commits it with the dress',
    (tester) async {
      final repo = FakeCatalogue()
        ..records['dress-1'] = sampleDress()
        ..saveError = StateError('Synthetic failure');
      await editor(
        tester,
        repo,
        () async =>
            XFile.fromData(fixture(), path: 'dress.png', name: 'dress.png'),
      );
      await select(tester);
      expect(find.text('New photo · saved with the dress'), findsOneWidget);
      expect(repo.photos, isEmpty);
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.photos, isEmpty);
      expect(find.text('Synthetic failure'), findsOneWidget);
      expect(find.text('New photo · saved with the dress'), findsOneWidget);
      repo.saveError = null;
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.photos.length, 1);
      expect(repo.records['dress-1']!.photoRevision, 2);
      expect(repo.records['dress-1']!.imageUrl, isEmpty);
    },
  );
  testWidgets('Removing photo blocks publication; undo restores it', (
    tester,
  ) async {
    final repo = FakeCatalogue();
    await editor(tester, repo, () async => null);
    await tester.tap(find.text('Remove photo'));
    await tester.tap(find.text('Save Dress'));
    await tester.pumpAndSettle();
    expect(find.text('Add a photo before publishing'), findsOneWidget);
    expect(repo.saves, 0);
    await tester.tap(find.text('Undo photo change'));
    await tester.pumpAndSettle();
    expect(find.text('Add a photo before publishing'), findsNothing);
    expect(find.text('Replace photo'), findsOneWidget);
  });

  Future<void> fillNewDress(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'Test satin gown');
    await tester.enterText(find.byType(TextFormField).at(1), '899');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'A satin gown with a full skirt and a sweetheart neckline.',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Colour'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ivory').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'M'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add Dress saves directly with AR try-on off by default', (
    tester,
  ) async {
    final repo = FakeCatalogue();
    await editor(tester, repo, () async => null, creating: true);
    final toggle = find.widgetWithText(SwitchListTile, 'AR try-on');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('AR model (optional)'), findsNothing);
    expect(find.text('Save & manage 3D try-on'), findsNothing);
    await fillNewDress(tester);
    await tester.tap(find.text('Save Dress'));
    await tester.pumpAndSettle();
    expect(repo.records['dress-1']!.arModelId, isEmpty);
    expect(repo.saves, 1);
    expect(find.byType(DressArDialog), findsNothing);
  });

  testWidgets(
    'Add Dress with AR requires a photo, consent, and a successful save',
    (tester) async {
      final repo = FakeCatalogue()..saveError = StateError('Save interrupted');
      await editor(
        tester,
        repo,
        () async =>
            XFile.fromData(fixture(), path: 'dress.png', name: 'dress.png'),
        creating: true,
      );
      await fillNewDress(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'AR try-on'));
      await tester.pumpAndSettle();
      final start = find.text('Save & generate AR');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.text('Upload a photo to generate AR try-on'), findsOneWidget);
      expect(repo.saves, 0);
      await select(tester, 'Upload photo');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.textContaining('about 30 Tripo API credits'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & generate'));
      await tester.pumpAndSettle();
      expect(find.text('Save interrupted'), findsOneWidget);
      expect(find.byType(DressArDialog), findsNothing);
      repo.saveError = null;
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & generate'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DressArDialog>(find.byType(DressArDialog));
      expect(dialog.generateOnOpen, isTrue);
      expect(dialog.dressId, 'dress-1');
      expect(dialog.photoRevision, 1);
      expect(repo.photos['dress-1'], isNotNull);
    },
  );
  testWidgets(
    'Stored photo is displayed and removed from view when access/data disappears',
    (tester) async {
      final repo = FakeCatalogue()
        ..photos['dress-1'] = compressDressPhoto(fixture());
      addTearDown(repo.changes.close);
      final dress = CatalogueDress.fromFields('dress-1', {
        ...sampleDress().toFields(),
        'imageUrl': '',
        'revision': 1,
        'photoRevision': 1,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogueDressPhoto(dress: dress, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      repo.photos.clear();
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Retry photo'), findsOneWidget);
    },
  );
}
