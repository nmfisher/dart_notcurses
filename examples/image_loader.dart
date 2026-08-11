// Shared helper for the examples: load an image file into an ncvisual.
//
// The vendored notcurses build is core-only and deliberately omits the
// FFmpeg/OpenImageIO multimedia engine (see native/src/shim.c), so
// Visual.fromFile() always fails. Decode the file in pure Dart instead and
// hand the raw pixels to Visual.fromRGBA(), which the core supports.
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:image/image.dart' as img;

/// Decode the image at [path] and return it as an ncvisual.
///
/// Throws [FileSystemException] if the file can't be read, [FormatException]
/// if it isn't a supported image, and any `image` package error on decode
/// failure. EXIF orientation (e.g. iPhone photos) is applied.
Visual loadImageFromFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('unable to decode image: $path');
  }
  final baked = img.bakeOrientation(decoded);
  final w = baked.width, h = baked.height;
  final rgba = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = baked.getPixel(x, y);
      rgba[o++] = p.r.toInt();
      rgba[o++] = p.g.toInt();
      rgba[o++] = p.b.toInt();
      rgba[o++] = p.a.toInt();
    }
  }
  return Visual.fromRGBA(rgba, h, w * 4, w);
}
