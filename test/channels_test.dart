import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Channel/Channels are pure bit math implemented via the C inline helpers, so
// they need the merged library but no terminal.
void main() {
  final skip = hasNotcursesLib ? null : 'notcurses merged library not built';

  group('Channel', () {
    test('initializer round-trips r/g/b and marks RGB in use', () {
      final c = Channel.initializer(0x11, 0x22, 0x33);
      expect(c.r, equals(0x11));
      expect(c.g, equals(0x22));
      expect(c.b, equals(0x33));
      expect(c.rgb, equals(0x112233));
      expect(c.isUsingRGB, isTrue);
      expect(c.isUsingDefault, isFalse);
    });

    test('setRGB8 / rgb8 round-trip', () {
      final c = Channel.initializer(0, 0, 0);
      expect(c.setRGB8(0xaa, 0xbb, 0xcc), isTrue);
      final rgb = c.rgb8();
      expect(rgb.r, equals(0xaa));
      expect(rgb.g, equals(0xbb));
      expect(rgb.b, equals(0xcc));
    });

    test('setRGB8 rejects out-of-range components', () {
      final c = Channel.initializer(0, 0, 0);
      expect(c.setRGB8(300, 0, 0), isFalse);
    });

    test('alpha round-trip', () {
      final c = Channel.initializer(1, 2, 3);
      expect(c.setAlpha(Alpha.transparent), isTrue);
      expect(c.alpha(), equals(Alpha.transparent));
      expect(c.setAlpha(Alpha.opaque), isTrue);
      expect(c.alpha(), equals(Alpha.opaque));
    });

    test('palette index round-trip', () {
      final c = Channel.initializer(1, 2, 3);
      expect(c.setPalindex(42), isTrue);
      expect(c.palindex(), equals(42));
      expect(c.isUsingPalindex, isTrue);
      expect(c.isUsingRGB, isFalse);
    });

    test('setDefault marks the channel default', () {
      final c = Channel.initializer(1, 2, 3);
      expect(c.isUsingDefault, isFalse);
      c.setDefault();
      expect(c.isUsingDefault, isTrue);
    });
  }, skip: skip);

  group('Channels', () {
    test('initializer round-trips fg and bg', () {
      final ch = Channels.initializer(0x11, 0x22, 0x33, 0x44, 0x55, 0x66);
      final fg = ch.fgRGB8();
      final bg = ch.bgRGB8();
      expect([fg.r, fg.g, fg.b], equals([0x11, 0x22, 0x33]));
      expect([bg.r, bg.g, bg.b], equals([0x44, 0x55, 0x66]));
      expect(ch.fgRGB(), equals(0x112233));
      expect(ch.bgRGB(), equals(0x445566));
    });

    test('combine assembles fg/bg channels', () {
      final f = Channel.initializer(0x10, 0x20, 0x30);
      final b = Channel.initializer(0x40, 0x50, 0x60);
      final ch = Channels.combine(f, b);
      expect(ch.fgRGB(), equals(0x102030));
      expect(ch.bgRGB(), equals(0x405060));
    });

    test('setFgRGB8/setBgRGB8 mutate in place', () {
      final ch = Channels.zero();
      expect(ch.setFgRGB8(1, 2, 3), isTrue);
      expect(ch.setBgRGB8(4, 5, 6), isTrue);
      expect(ch.fgRGB(), equals(0x010203));
      expect(ch.bgRGB(), equals(0x040506));
    });

    test('copy is independent of the original', () {
      final a = Channels.initializer(1, 2, 3, 4, 5, 6);
      final b = a.copy();
      b.setFgRGB8(0x99, 0x99, 0x99);
      expect(a.fgRGB(), equals(0x010203));
      expect(b.fgRGB(), equals(0x999999));
    });

    test('alpha round-trip on both channels', () {
      final ch = Channels.initializer(1, 2, 3, 4, 5, 6);
      expect(ch.setFgAlpha(Alpha.blend), isTrue);
      expect(ch.fgAlpha(), equals(Alpha.blend));
      expect(ch.setBgAlpha(Alpha.transparent), isTrue);
      expect(ch.bgAlpha(), equals(Alpha.transparent));
    });

    test('palette index round-trip', () {
      final ch = Channels.zero();
      expect(ch.setFgPalindex(7), isTrue);
      expect(ch.fgPalindex(), equals(7));
      expect(ch.setBgPalindex(9), isTrue);
      expect(ch.bgPalindex(), equals(9));
    });

    test('reverse swaps fg and bg color info', () {
      final ch = Channels.initializer(0x11, 0x22, 0x33, 0x44, 0x55, 0x66);
      final rev = Channels.from(ch.reverse());
      expect(rev.fgRGB(), equals(0x445566));
      expect(rev.bgRGB(), equals(0x112233));
    });

    // Regression: setChannels used `==` instead of `=` and silently
    // discarded the update.
    test('setChannels copies color/alpha bits from another pair', () {
      final src = Channels.initializer(0x11, 0x22, 0x33, 0x44, 0x55, 0x66);
      final dst = Channels.initializer(0x01, 0x02, 0x03, 0x04, 0x05, 0x06);
      dst.setChannels(src.channels());
      expect(dst.fgRGB(), equals(0x112233));
      expect(dst.bgRGB(), equals(0x445566));
    });
  }, skip: skip);
}
