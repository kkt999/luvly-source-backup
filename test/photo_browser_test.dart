import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luvly_app/catalogue/dress_photo_data.dart';

void main() {
  // Run with --platform chrome as well as the default VM test renderer.
  testWidgets('stored JPEG rendering copy decodes successfully', (t) async {
    final photo = DressPhotoData.fromFields(
      compressDressPhoto(
        img.encodePng(img.Image(width: 100, height: 150)),
      ).toFields(),
    );
    Object? failure;
    expect(identical(photo.imageBytes, photo.bytes), isFalse);
    expect(photo.imageBytes, photo.bytes);
    bool decoded = false;
    await t.pumpWidget(
      MaterialApp(
        home: Image.memory(
          photo.imageBytes,
          frameBuilder: (context, child, frame, sync) {
            if (frame != null || sync) decoded = true;
            return child;
          },
          errorBuilder: (context, error, stack) {
            failure = error;
            return const SizedBox();
          },
        ),
      ),
    );
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await t.pump();
    expect(failure, isNull);
    expect(decoded, isTrue);
  });
}
