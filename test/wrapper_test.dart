import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

void main() {
  group('Capabilities', () {
    test('defaults octants to false', () {
      const caps = Capabilities();
      expect(caps.octants, isFalse);
    });

    test('accepts octants: true', () {
      const caps = Capabilities(octants: true);
      expect(caps.octants, isTrue);
    });

    test('toString includes octants', () {
      const caps = Capabilities(octants: true);
      expect(caps.toString(), contains('octants'));
    });

    test('preserves all existing fields', () {
      const caps = Capabilities(
        colors: 256,
        utf8: true,
        rgb: true,
        canChangeColors: true,
        halfblocks: true,
        quadrants: true,
        sextants: true,
        braille: true,
        octants: true,
      );
      expect(caps.colors, 256);
      expect(caps.utf8, isTrue);
      expect(caps.rgb, isTrue);
      expect(caps.canChangeColors, isTrue);
      expect(caps.halfblocks, isTrue);
      expect(caps.quadrants, isTrue);
      expect(caps.sextants, isTrue);
      expect(caps.braille, isTrue);
      expect(caps.octants, isTrue);
    });
  });

  group('Blitter', () {
    test('blit_4x2 is a valid int', () {
      expect(Blitter.blit_4x2, isA<int>());
      expect(Blitter.blit_4x2, greaterThanOrEqualTo(0));
    });

    test('blit_4x2 equals NCBLIT_4x2 from FFI enum', () {
      expect(Blitter.blit_4x2, equals(9));
    });
  });
}
