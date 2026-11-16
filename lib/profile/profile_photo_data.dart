import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../catalogue/dress_photo_data.dart';

const maxAvatarBytes = 64 * 1024;

class ProfilePhotoRecord {
  ProfilePhotoRecord(this.uid, this.revision, this.photo);
  final String uid;
  final int revision;
  final DressPhotoData? photo;
  factory ProfilePhotoRecord.parse(Map<String, dynamic> value, String owner) {
    if (value['uid'] != owner ||
        value['revision'] is! int ||
        value['revision'] < 0 ||
        !value.containsKey('photo')) {
      throw const FormatException('Invalid photo record');
    }
    DressPhotoData? photo;
    if (value['photo'] != null) {
      photo = DressPhotoData.fromFields(
        Map<String, dynamic>.from(value['photo']),
      );
      if (photo.bytes.length > maxAvatarBytes ||
          photo.width != photo.height ||
          photo.width < 64 ||
          photo.width > 512) {
        throw const FormatException('Invalid profile photo');
      }
    }
    return ProfilePhotoRecord(owner, value['revision'], photo);
  }
}

/// The same integer crop is used by both the preview painter and saved image.
({int x, int y, int side}) profileCropBounds(
  int width,
  int height,
  double zoom,
  double x,
  double y,
) {
  if (width < 64 ||
      height < 64 ||
      !zoom.isFinite ||
      zoom < 1 ||
      zoom > 3 ||
      !x.isFinite ||
      !y.isFinite) {
    throw const FormatException('Invalid crop');
  }
  final side = (math.min(width, height) / zoom)
      .floor()
      .clamp(64, math.min(width, height))
      .toInt();
  return (
    x: ((width - side) * x.clamp(0, 1)).round(),
    y: ((height - side) * y.clamp(0, 1)).round(),
    side: side,
  );
}

class ProfileCropInput {
  const ProfileCropInput(this.bytes, this.zoom, this.x, this.y);
  final Uint8List bytes;
  final double zoom, x, y;
}

Future<DressPhotoData> prepareProfileCrop(ProfileCropInput input) =>
    compute(encodeProfileCrop, input);
DressPhotoData encodeProfileCrop(ProfileCropInput input) {
  final source = img.decodeJpg(input.bytes);
  if (source == null || source.width > 1200 || source.height > 1200) {
    throw const FormatException('Could not read this photo.');
  }
  final b = profileCropBounds(
    source.width,
    source.height,
    input.zoom,
    input.x,
    input.y,
  );
  var crop = img.copyCrop(
    source,
    x: b.x,
    y: b.y,
    width: b.side,
    height: b.side,
  );
  if (crop.width > 512) {
    crop = img.copyResize(
      crop,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.average,
    );
  }
  // A new pixel canvas strips all source metadata before JPEG encoding.
  final clean = img.Image(
    width: crop.width,
    height: crop.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, crop);
  for (final quality in [85, 75, 60, 45, 30]) {
    final bytes = img.encodeJpg(clean, quality: quality);
    if (bytes.length <= maxAvatarBytes) {
      return DressPhotoData.fromFields({
        'data': base64Encode(bytes),
        'mime': 'image/jpeg',
        'width': clean.width,
        'height': clean.height,
      });
    }
  }
  throw const FormatException(
    'Could not prepare a small profile photo. Choose a simpler image.',
  );
}
