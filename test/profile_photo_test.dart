import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/profile/profile_photo_data.dart';
import 'package:luvly_app/profile/profile_photo.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/workspace/workspace_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'checkout_redesign_test.dart' show fonts, viewport;

Uint8List picture({int width = 128, int height = 192}) {
  final value = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      value.setPixelRgb(
        x,
        y,
        x < width ~/ 2 ? 180 : 30,
        80,
        x < width ~/ 2 ? 100 : 170,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(value, quality: 90));
}

DressPhotoData storedPhoto() =>
    encodeProfileCrop(ProfileCropInput(picture(), 1, .5, .5));

class PhotoApi extends WorkspaceApi {
  String uid = 'bride';
  int revision = 0;
  Map<String, dynamic>? photo;
  bool failRead = false, failSave = false;
  final posts = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body == null) {
      if (failRead) {
        throw const PaymentFailure('Photo service unavailable. Retry.');
      }
    } else {
      posts.add(Map.of(body));
      if (failSave) throw const PaymentFailure('Upload not confirmed. Retry.');
      if (body['revision'] != revision) {
        throw const PaymentFailure('Photo changed on another device.');
      }
      photo = body['photo'] == null
          ? null
          : Map<String, dynamic>.from(body['photo']);
      revision++;
    }
    return {'uid': uid, 'revision': revision, 'photo': photo};
  }
}

Future<void> settleWork(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (ready()) {
      await t.pumpAndSettle();
      return;
    }
  }
  fail(
    'Photo operation did not finish: ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? "[rich]").join(" | ")}',
  );
}

Future<void> host(
  WidgetTester t,
  PhotoApi api, {
  Future<XFile?> Function()? pick,
  double width = 390,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => Column(
            children: [
              ProfilePhotoAvatar(uid: 'bride', api: api),
              TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<String>(
                    builder: (_) => ProfilePhotoEditScreen(
                      uid: 'bride',
                      api: api,
                      pickPhoto:
                          pick ??
                          () async => XFile.fromData(
                            picture(),
                            path: 'portrait.jpg',
                            name: 'portrait.jpg',
                            mimeType: 'image/jpeg',
                          ),
                    ),
                  ),
                ),
                child: const Text('Open photo editor'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('Open photo editor'));
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t) async {
  await t.ensureVisible(find.text('Choose photo'));
  await t.tap(find.text('Choose photo'));
  await settleWork(t, () => find.text('Choose another').evaluate().isNotEmpty);
}

void main() {
  setUpAll(fonts);
  test('crop positions and zoom share exact bounded square geometry', () {
    expect(profileCropBounds(200, 100, 1, 0, .5), (x: 0, y: 0, side: 100));
    expect(profileCropBounds(200, 100, 1, 1, .5), (x: 100, y: 0, side: 100));
    expect(profileCropBounds(200, 100, 2, .5, .5), (x: 68, y: 18, side: 64));
    expect(() => profileCropBounds(63, 100, 1, .5, .5), throwsFormatException);
    expect(
      () => profileCropBounds(200, 100, double.nan, .5, .5),
      throwsFormatException,
    );
  });
  test('saved JPEG is the displayed crop, square, small and readable', () {
    final bytes = picture(width: 256, height: 128),
        left = encodeProfileCrop(ProfileCropInput(bytes, 1, 0, .5)),
        right = encodeProfileCrop(ProfileCropInput(bytes, 1, 1, .5));
    expect(left.width, left.height);
    expect(left.bytes.length, lessThanOrEqualTo(maxAvatarBytes));
    final l = img.decodeJpg(left.bytes)!.getPixel(64, 64),
        r = img.decodeJpg(right.bytes)!.getPixel(64, 64);
    expect(l.r, greaterThan(r.r));
    expect(r.b, greaterThan(l.b));
    expect(left.toFields()['mime'], 'image/jpeg');
  });
  test(
    'large source is reduced to at most 512px without losing square ratio',
    () {
      final result = encodeProfileCrop(
        ProfileCropInput(picture(width: 900, height: 1100), 1, .5, .5),
      );
      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.bytes.length, lessThanOrEqualTo(65536));
    },
  );
  test('photo record rejects another owner and non-square stored image', () {
    final photo = storedPhoto().toFields();
    expect(
      () => ProfilePhotoRecord.parse({
        'uid': 'other',
        'revision': 1,
        'photo': photo,
      }, 'bride'),
      throwsFormatException,
    );
    expect(
      () => ProfilePhotoRecord.parse({
        'uid': 'bride',
        'revision': -1,
        'photo': null,
      }, 'bride'),
      throwsFormatException,
    );
    expect(
      () => ProfilePhotoRecord.parse({
        'uid': 'bride',
        'revision': 1,
        'photo': {...photo, 'height': 64},
      }, 'bride'),
      throwsFormatException,
    );
  });
  testWidgets('selection is only a preview; cancel never uploads', (t) async {
    final api = PhotoApi();
    addTearDown(api.close);
    await host(t, api);
    await choose(t);
    expect(api.posts, isEmpty);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Discard photo changes?'), findsOneWidget);
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(api.photo, isNull);
    expect(api.posts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('cancelling the picker leaves the saved photo untouched', (
    t,
  ) async {
    final original = storedPhoto().toFields();
    final api = PhotoApi()
      ..photo = original
      ..revision = 1;
    addTearDown(api.close);
    await host(t, api, pick: () async => null);
    await t.ensureVisible(find.text('Choose photo'));
    await t.tap(find.text('Choose photo'));
    await t.pumpAndSettle();
    expect(find.text('Choose another'), findsNothing);
    expect(api.posts, isEmpty);
    expect(api.photo, original);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Discard photo changes?'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('save uploads the crop and refreshes the profile avatar', (
    t,
  ) async {
    final api = PhotoApi();
    addTearDown(api.close);
    await host(t, api);
    await choose(t);
    await t.ensureVisible(find.text('Save photo'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save photo'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await t.tap(find.text('Save photo'));
    await t.pump();
    expect(find.text('Saving…'), findsOneWidget);
    await settleWork(
      t,
      () =>
          find.text('Open photo editor').evaluate().isNotEmpty &&
          find.text('Profile photo').evaluate().isEmpty,
    );
    expect(api.posts.length, 1);
    expect(api.posts.first.keys.toSet(), {'requestId', 'revision', 'photo'});
    expect(api.photo!['width'], api.photo!['height']);
    expect(find.byType(Image), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('failed upload retains preview and reuses the request on retry', (
    t,
  ) async {
    final api = PhotoApi()..failSave = true;
    addTearDown(api.close);
    await host(t, api);
    await choose(t);
    await t.ensureVisible(find.text('Save photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save photo'));
    await settleWork(
      t,
      () => find.text('Upload not confirmed. Retry.').evaluate().isNotEmpty,
    );
    expect(api.photo, isNull);
    expect(find.text('Choose another'), findsOneWidget);
    final first = api.posts.first;
    api.failSave = false;
    await t.ensureVisible(find.text('Save photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save photo'));
    await settleWork(
      t,
      () =>
          api.photo != null &&
          find.byType(ProfilePhotoEditScreen).evaluate().isEmpty,
    );
    expect(api.posts.last['requestId'], first['requestId']);
    expect(api.posts.last['photo'], first['photo']);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'remove asks confirmation and persists removal only after approval',
    (t) async {
      final api = PhotoApi()
        ..photo = storedPhoto().toFields()
        ..revision = 1;
      addTearDown(api.close);
      await host(t, api);
      await t.ensureVisible(find.text('Remove photo'));
      await t.tap(find.text('Remove photo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep photo'));
      await t.pumpAndSettle();
      expect(api.posts, isEmpty);
      expect(api.photo, isNotNull);
      await t.tap(find.text('Remove photo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove').last);
      await t.pumpAndSettle();
      expect(api.photo, isNull);
      expect(api.revision, 2);
      expect(find.byType(ProfilePhotoEditScreen), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed initial load is not reported as a missing photo', (
    t,
  ) async {
    final api = PhotoApi()..failRead = true;
    addTearDown(api.close);
    await host(t, api);
    expect(find.text('Photo service unavailable. Retry.'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save photo'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    api.failRead = false;
    await t.tap(find.text('Retry photo'));
    await t.pumpAndSettle();
    expect(find.text('Photo service unavailable. Retry.'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('bad file never uploads or replaces the saved photo', (t) async {
    final api = PhotoApi()
      ..photo = storedPhoto().toFields()
      ..revision = 1;
    addTearDown(api.close);
    await host(
      t,
      api,
      pick: () async => XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        path: 'bad.jpg',
        name: 'bad.jpg',
      ),
    );
    await t.ensureVisible(find.text('Choose photo'));
    await t.tap(find.text('Choose photo'));
    await settleWork(
      t,
      () => find
          .text('This file is not a JPG or PNG photo.')
          .evaluate()
          .isNotEmpty,
    );
    expect(api.posts, isEmpty);
    expect(api.photo, isNotNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('account switch clears previously displayed image', (t) async {
    final api = PhotoApi()..photo = storedPhoto().toFields();
    addTearDown(api.close);
    Widget app(String uid) => MaterialApp(
      home: Scaffold(
        body: ProfilePhotoAvatar(uid: uid, api: api),
      ),
    );
    await t.pumpWidget(app('bride'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    api.uid = 'other';
    api.photo = null;
    await t.pumpWidget(app('other'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 1100.0]) {
    testWidgets('photo preview fits $width at double text scale', (t) async {
      final api = PhotoApi();
      addTearDown(api.close);
      await host(t, api, width: width, scale: 2);
      await choose(t);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).last, const Offset(0, -650));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('profile photo editor visual with a synthetic crop', (t) async {
    final api = PhotoApi();
    addTearDown(api.close);
    await host(t, api);
    await choose(t);
    await t.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile('previews/profile-photo-editor-2076.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
}
