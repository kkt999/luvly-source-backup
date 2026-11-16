import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const maxPhotoInputBytes = 5 * 1024 * 1024;
const maxPhotoBytes = 200 * 1024;
const maxPhotoBase64Length = 273068;

/// A small, metadata-free JPEG; originals are never uploaded.
class DressPhotoData {
  DressPhotoData._(this.bytes, this.width, this.height);
  final Uint8List bytes;
  // Flutter's JS renderer passes image buffers directly to browser WebCodecs.
  // A Dart unmodifiable-list wrapper is not a native JS Uint8Array. Keep the
  // validated storage bytes immutable and give the renderer its own typed copy.
  late final Uint8List imageBytes = Uint8List.fromList(bytes);
  final int width, height;

  Map<String, dynamic> toFields() => {
    'data': base64Encode(bytes),
    'mime': 'image/jpeg',
    'width': width,
    'height': height,
  };

  factory DressPhotoData.fromFields(Map<String, dynamic> fields) {
    final data = fields['data'];
    final width = fields['width'];
    final height = fields['height'];
    if (fields['mime'] != 'image/jpeg' ||
        data is! String ||
        data.length > maxPhotoBase64Length ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > 1200 ||
        height > 1200) {
      throw const FormatException('Invalid stored photo');
    }
    final bytes = base64Decode(data);
    if (bytes.length > maxPhotoBytes ||
        bytes.length < 4 ||
        bytes[0] != 255 ||
        bytes[1] != 216 ||
        bytes[bytes.length - 2] != 255 ||
        bytes.last != 217) {
      throw const FormatException('Invalid stored photo');
    }
    try {
      final info = img.JpegDecoder().startDecode(bytes);
      if (info == null ||
          info.width != width ||
          info.height != height ||
          info.numFrames != 1) {
        throw const FormatException('Invalid stored photo dimensions');
      }
    } catch (_) {
      throw const FormatException('Invalid stored photo');
    }
    return DressPhotoData._(bytes.asUnmodifiableView(), width, height);
  }
}

Future<XFile?> selectDressPhoto() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Dress photos',
      extensions: ['jpg', 'jpeg', 'png'],
      mimeTypes: ['image/jpeg', 'image/png'],
      uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
    ),
  ],
);

Future<DressPhotoData> prepareDressPhoto(XFile file) async {
  final extension = file.name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png'].contains(extension)) {
    throw const FormatException('Choose a JPG or PNG photo.');
  }
  if (await file.length() > maxPhotoInputBytes) {
    throw const FormatException('Choose a photo smaller than 5 MB.');
  }
  final bytes = await file.readAsBytes();
  // compute uses a worker isolate on mobile/desktop; web executes locally.
  return compute(compressDressPhoto, bytes);
}

DressPhotoData compressDressPhoto(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxPhotoInputBytes) {
    throw const FormatException('Choose a non-empty photo smaller than 5 MB.');
  }
  try {
    final img.Decoder decoder;
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      decoder = img.JpegDecoder();
    } else if (bytes.length >= 8 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
      decoder = img.PngDecoder();
    } else {
      throw const FormatException('This file is not a JPG or PNG photo.');
    }
    final info = decoder.startDecode(bytes);
    if (info == null) throw const FormatException('Unable to read this photo.');
    if (info.width < 64 ||
        info.height < 64 ||
        info.width > 6000 ||
        info.height > 6000 ||
        info.width * info.height > 12000000) {
      throw const FormatException(
        'Choose a photo at least 64 × 64 pixels and no larger than 12 megapixels (6,000 pixels per side).',
      );
    }
    if (info.numFrames > 1) {
      throw const FormatException('Choose a still photo, not an animation.');
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) throw const FormatException('This photo is damaged.');
    var oriented = img.bakeOrientation(decoded);
    if (oriented.width > 1200 || oriented.height > 1200) {
      oriented = img.copyResize(
        oriented,
        width: oriented.width >= oriented.height ? 1200 : null,
        height: oriented.height > oriented.width ? 1200 : null,
        interpolation: img.Interpolation.average,
      );
    }
    // Copy pixels onto a new white canvas: no EXIF/GPS/other metadata survives.
    var clean = img.Image(
      width: oriented.width,
      height: oriented.height,
      numChannels: 3,
    );
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, oriented);
    for (var attempt = 0; attempt < 8; attempt++) {
      final jpeg = img.encodeJpg(clean, quality: attempt == 0 ? 85 : 75);
      if (jpeg.length <= maxPhotoBytes) {
        return DressPhotoData._(
          jpeg.asUnmodifiableView(),
          clean.width,
          clean.height,
        );
      }
      clean = img.copyResize(
        clean,
        width: (clean.width * .8).round(),
        height: (clean.height * .8).round(),
        interpolation: img.Interpolation.average,
      );
    }
    throw const FormatException(
      'Unable to compress this photo. Choose a smaller one.',
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'This photo is damaged or unsupported. Choose another JPG or PNG.',
    );
  }
}
