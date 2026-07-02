import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Cell wraps a calloc'd nccell manipulated via C inline helpers; no terminal
// needed as long as the cell is never loaded against a plane.
void main() {
  final skip = hasNotcursesLib ? null : 'notcurses merged library not built';

  group('Cell', () {
    test('init produces a defaulted cell', () {
      final c = Cell.init();
      expect(c.styles(), equals(0));
      expect(c.fgDefaultP(), isTrue);
      expect(c.bgDefaultP(), isTrue);
      c.destroy(null);
    });

    test('style bits round-trip', () {
      final c = Cell.init();
      c.setStyles(Style.bold);
      expect(c.styles(), equals(Style.bold));
      c.onStyles(Style.italic);
      expect(c.styles(), equals(Style.bold | Style.italic));
      c.offStyles(Style.bold);
      expect(c.styles(), equals(Style.italic));
      c.destroy(null);
    });

    test('fg RGB round-trip', () {
      final c = Cell.init();
      expect(c.setFgRGB8(const RGB(0xaa, 0xbb, 0xcc)), isTrue);
      final rgb = c.fgRGB8();
      expect([rgb.r, rgb.g, rgb.b], equals([0xaa, 0xbb, 0xcc]));
      expect(c.fgDefaultP(), isFalse);
      c.destroy(null);
    });

    // Regression: setFgDefault() used to call nccell_set_bg_default.
    test('setFgDefault resets the foreground, not the background', () {
      final c = Cell.init();
      c.setFgRGB8(const RGB(1, 2, 3));
      c.setBgRGB8(const RGB(4, 5, 6));
      expect(c.fgDefaultP(), isFalse);
      expect(c.bgDefaultP(), isFalse);

      c.setFgDefault();
      expect(c.fgDefaultP(), isTrue, reason: 'foreground must go default');
      expect(c.bgDefaultP(), isFalse, reason: 'background must be untouched');

      c.setBgDefault();
      expect(c.bgDefaultP(), isTrue);
      c.destroy(null);
    });

    test('alpha round-trip', () {
      final c = Cell.init();
      c.setFgRGB8(const RGB(1, 2, 3));
      expect(c.setFgAlpha(Alpha.transparent), equals(0));
      expect(c.fgAlpha(), equals(Alpha.transparent));
      c.destroy(null);
    });

    test('palette index round-trip', () {
      final c = Cell.init();
      expect(c.setFgPalindex(5), equals(0));
      expect(c.fgPalindexP(), isTrue);
      c.destroy(null);
    });

    test('destroy is idempotent', () {
      final c = Cell.init();
      c.destroy(null);
      expect(() => c.destroy(null), returnsNormally);
      expect(() => c.destroy(null), returnsNormally);
    });

    test('init/destroy loop does not crash', () {
      for (var i = 0; i < 1000; i++) {
        final c = Cell.init();
        c.setStyles(Style.bold);
        c.destroy(null);
      }
    });
  }, skip: skip);
}
