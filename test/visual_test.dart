import 'dart:typed_data';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// ncvisual construction and pixel access operate on memory only — no
// initialized notcurses context or terminal required.
void main() {
  final skip = hasNotcursesLib ? null : 'notcurses merged library not built';

  group('Visual', () {
    test('fromRGBA constructs from a correctly sized buffer', () {
      const rows = 4, cols = 4, rowstride = cols * 4;
      final pixels = Uint8List(rows * rowstride);
      final v = Visual.fromRGBA(pixels, rows, rowstride, cols);
      expect(v.initialized, isTrue);
      v.destroy();
    });

    // Regression: the C library reads rows*rowstride bytes; an undersized
    // Dart buffer used to be passed through and over-read.
    test('fromRGBA rejects an undersized buffer', () {
      const rows = 4, cols = 4, rowstride = cols * 4;
      final tooSmall = Uint8List(rows * rowstride ~/ 2);
      expect(
        () => Visual.fromRGBA(tooSmall, rows, rowstride, cols),
        throwsArgumentError,
      );
    });

    test('fromPalidx rejects a palette smaller than palsize', () {
      const rows = 2, cols = 2, pstride = 1, rowstride = cols * pstride;
      final data = Uint8List(rows * rowstride);
      final palette = Uint32List(2);
      expect(
        () => Visual.fromPalidx(data, rows, rowstride, cols, 8, pstride, palette),
        throwsArgumentError,
      );
    });

    test('setYX/atYX round-trip a pixel', () {
      const rows = 4, cols = 4, rowstride = cols * 4;
      final v = Visual.fromRGBA(Uint8List(rows * rowstride), rows, rowstride, cols);
      expect(v.initialized, isTrue);
      const pixel = 0xffcc8844;
      expect(v.setYX(1, 2, pixel), isTrue);
      expect(v.atYX(1, 2), equals(pixel));
      expect(v.atYX(99, 99), isNull);
      v.destroy();
    });

    test('fromFile with a missing path is notInitialized', () {
      final v = Visual.fromFile('/nonexistent/no-such-image.png');
      expect(v.notInitialized, isTrue);
      // Destroying a failed visual must be a no-op, not a crash.
      expect(v.destroy, returnsNormally);
    });

    test('destroy is idempotent', () {
      const rows = 2, cols = 2, rowstride = cols * 4;
      final v = Visual.fromRGBA(Uint8List(rows * rowstride), rows, rowstride, cols);
      v.destroy();
      expect(v.destroy, returnsNormally);
      expect(v.notInitialized, isTrue);
    });

    // Finalizer smoke: undisposed visuals are reclaimed by GC without
    // crashing; explicitly destroyed ones must be detached (a missed detach
    // would double-free on a later GC).
    test('undisposed visuals are reclaimed without crashing', () {
      const rows = 8, cols = 8, rowstride = cols * 4;
      for (var i = 0; i < 100; i++) {
        Visual.fromRGBA(Uint8List(rows * rowstride), rows, rowstride, cols);
        Visual.fromRGBA(Uint8List(rows * rowstride), rows, rowstride, cols).destroy();
      }
      var sink = 0;
      for (var i = 0; i < 50; i++) {
        sink += List<int>.generate(64 * 1024, (j) => j).length;
      }
      expect(sink, greaterThan(0));
    });
  }, skip: skip);
}
