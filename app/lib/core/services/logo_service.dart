import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

/// The longest side, in pixels, an uploaded logo is allowed to keep. Small
/// enough that a downscaled PNG travels comfortably in the profile JSON.
const int kLogoMaxSide = 256;

/// Reads an image the owner chose for their business logo.
///
/// Isolated behind an interface so the setup flow can be tested without a
/// real file picker, and so a platform without one simply returns null and
/// leaves the first-letter fallback in place.
abstract class LogoService {
  /// The chosen image encoded as PNG bytes, or null when the owner cancelled.
  Future<Uint8List?> pick();
}

class DeviceLogoService implements LogoService {
  const DeviceLogoService();

  @override
  Future<Uint8List?> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final raw = await file.readAsBytes();
    return downscaleToPng(raw);
  }
}

/// Re-encodes [raw] as a PNG no larger than [kLogoMaxSide] on its longest side.
///
/// The picker can hand back a multi-megabyte photo; decoding and re-encoding
/// here keeps every platform (web included, which ignores the picker's own
/// resize options) sending the same small, predictable payload.
Future<Uint8List?> downscaleToPng(Uint8List raw) async {
  final decoder = await ui.instantiateImageCodec(raw);
  final frame = await decoder.getNextFrame();
  final source = frame.image;
  try {
    final longest = math.max(source.width, source.height);
    final scale = longest > kLogoMaxSide ? kLogoMaxSide / longest : 1.0;

    if (scale >= 1.0) {
      final data = await source.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    }

    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final resizedDecoder = await ui.instantiateImageCodec(
      raw,
      targetWidth: width,
      targetHeight: height,
    );
    try {
      final resized = (await resizedDecoder.getNextFrame()).image;
      try {
        final data = await resized.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        resized.dispose();
      }
    } finally {
      resizedDecoder.dispose();
    }
  } finally {
    source.dispose();
    decoder.dispose();
  }
}
