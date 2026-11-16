import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PreparedDeliveryPhoto {
  final Uint8List bytes;
  final String capturedAt;
  const PreparedDeliveryPhoto(this.bytes, this.capturedAt);
}

/// Runs in an isolate. Always emits an upright JPEG without GPS/EXIF metadata.
Uint8List prepareDeliveryPhoto(Uint8List source) =>
    _prepare(source, DateTime.now().toUtc().toIso8601String()).bytes;

PreparedDeliveryPhoto prepareCapturedDeliveryPhoto(
  Map<String, dynamic> input,
) => _prepare(input['bytes'] as Uint8List, input['received_at'] as String);

PreparedDeliveryPhoto _prepare(Uint8List source, String receivedAt) {
  final decoder = img.findDecoderForData(source);
  if (decoder == null ||
      !{
        img.ImageFormat.jpg,
        img.ImageFormat.png,
        img.ImageFormat.webp,
      }.contains(decoder.format)) {
    throw const FormatException('Take a JPEG, PNG, or WebP photo.');
  }
  final info = decoder.startDecode(source);
  if (info == null || math.min(info.width, info.height) < 640) {
    throw const FormatException(
      'Retake the photo at a resolution of at least 640 pixels on each side.',
    );
  }
  if (info.width * info.height > 40000000) {
    throw const FormatException(
      'Use a camera resolution of at most 40 megapixels and retake the photo.',
    );
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('Unable to read the photo. Please retake it.');
  }
  // Native camera confirmation can happen after the shutter. Prefer the camera's
  // original EXIF time; fall back to the time its result reached the app.
  final original = decoded.exif.exifIfd[0x9003]?.toString().trim();
  final offset = decoded.exif.exifIfd[0x9011]?.toString().trim() ?? '';
  String capturedAt = receivedAt;
  if (original != null &&
      RegExp(r'^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(original)) {
    final date =
        '${original.substring(0, 4)}-${original.substring(5, 7)}-${original.substring(8, 10)}T${original.substring(11)}';
    final zone = RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(offset) ? offset : '';
    capturedAt =
        DateTime.tryParse('$date$zone')?.toUtc().toIso8601String() ??
        receivedAt;
  }
  var photo = img.bakeOrientation(decoded);
  photo.exif = img.ExifData();
  var shortest = math.min(photo.width, photo.height);
  // Keep useful parcel detail while bounding memory and typical upload size.
  var target = math.min(shortest, 1600);
  while (true) {
    if (target < shortest) {
      final scale = target / shortest;
      photo = img.copyResize(
        photo,
        width: math.max(640, (photo.width * scale).round()),
        height: math.max(640, (photo.height * scale).round()),
      );
      shortest = math.min(photo.width, photo.height);
    }
    for (final quality in [88, 75, 60, 45]) {
      final bytes = img.encodeJpg(photo, quality: quality);
      if (bytes.length <= 5 * 1024 * 1024) {
        return PreparedDeliveryPhoto(bytes, capturedAt);
      }
    }
    if (shortest <= 640) break;
    target = math.max(640, (shortest * .8).floor());
  }
  throw const FormatException(
    'Reduce the camera resolution and retake the photo (maximum 5 MB).',
  );
}
