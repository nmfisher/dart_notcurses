import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:dart_notcurses/src/extensions/string.dart';
import 'package:test/test.dart';

// Pure-Dart surface: no native library required.
void main() {
  group('swap16/swap32', () {
    test('swap16 reverses byte order', () {
      expect(swap16(0x1234), equals(0x3412));
      expect(swap16(0x00ff), equals(0xff00));
      expect(swap16(0x0000), equals(0x0000));
      expect(swap16(swap16(0xbeef)), equals(0xbeef));
    });

    test('swap32 reverses byte order', () {
      expect(swap32(0x12345678), equals(0x78563412));
      expect(swap32(0x000000ff), equals(0xff000000));
      expect(swap32(swap32(0xdeadbeef)), equals(0xdeadbeef));
    });
  });

  group('NcResult', () {
    test('carries result and value', () {
      final r = NcResult<int, String?>(0, 'x');
      expect(r.result, equals(0));
      expect(r.value, equals('x'));
    });
  });

  group('extensions', () {
    test('toStrHex pads to the requested width', () {
      expect(0xff.toStrHex(padding: 4), equals('0x00ff'));
      expect(0x0.toStrHex(), equals('0x0'));
      expect(0xabc.toStrHex(padding: 2), equals('0xabc'));
    });

    test('padCenter centers within the given width', () {
      expect('ab'.padCenter(6).length, equals(6));
      expect('ab'.padCenter(6).trim(), equals('ab'));
      expect('abc'.padCenter(2), equals('abc'));
    });
  });

  group('NcKey / preterunicode', () {
    // Pinned to PRETERUNICODEBASE (1115000) in notcurses/nckeys.h.
    test('preterunicode offsets from the notcurses base', () {
      expect(preterunicode(1), equals(1115001));
    });

    test('synthesized key constants match nckeys.h', () {
      expect(NcKey.invalid, equals(1115000));
      expect(NcKey.resize, equals(1115001));
      expect(NcKey.up, equals(1115002));
      expect(NcKey.down, equals(1115004));
      expect(NcKey.f01, equals(1115021));
      expect(NcKey.enter, equals(1115121));
      expect(NcKey.motion, equals(1115200));
      expect(NcKey.button1, equals(1115201));
    });

    test('ncKeyStr maps known keys and falls back to unknown', () {
      expect(ncKeyStr(NcKey.resize), isNot(equals('unknown')));
      expect(ncKeyStr(0x41), equals('unknown'));
    });
  });

  group('KeyMod pins (nckeys.h NCKEY_MOD_*)', () {
    test('modifier bits match the C header', () {
      expect(KeyMod.shift, equals(1));
      expect(KeyMod.alt, equals(2));
      expect(KeyMod.ctrl, equals(4));
      expect(KeyMod.superx, equals(8));
      expect(KeyMod.hyper, equals(16));
      expect(KeyMod.meta, equals(32));
      expect(KeyMod.capslock, equals(64));
      expect(KeyMod.numlock, equals(128));
    });
  });

  group('ptypes pins (notcurses.h values)', () {
    // These protect against drift when the ffigen bindings are regenerated
    // against a different notcurses version.
    test('Blitter values match ncblitter_e', () {
      expect(Blitter.defaultt, equals(0));
      expect(Blitter.blit_1x1, equals(1));
      expect(Blitter.blit_2x1, equals(2));
      expect(Blitter.blit_2x2, equals(3));
      expect(Blitter.blit_3x2, equals(4));
      expect(Blitter.blit_4x2, equals(5));
      expect(Blitter.braille, equals(6));
      expect(Blitter.pixel, equals(7));
      expect(Blitter.blit_4x1, equals(8));
      expect(Blitter.blit_8x1, equals(9));
    });

    test('Style values match NCSTYLE_*', () {
      expect(Style.none, equals(0));
      expect(Style.struck, equals(0x1));
      expect(Style.bold, equals(0x2));
      expect(Style.undercurl, equals(0x4));
      expect(Style.underline, equals(0x8));
      expect(Style.italic, equals(0x10));
      expect(Style.mask, equals(0xffff));
    });

    test('Alpha values match NCALPHA_*', () {
      expect(Alpha.opaque, equals(0));
      expect(Alpha.blend, equals(0x10000000));
      expect(Alpha.transparent, equals(0x20000000));
      expect(Alpha.highcontrast, equals(0x30000000));
    });

    test('Align/Scale/EventType values match their enums', () {
      expect(Align.unaligned, equals(0));
      expect(Align.left, equals(1));
      expect(Align.center, equals(2));
      expect(Align.right, equals(3));
      expect(Scale.none, equals(0));
      expect(Scale.scaleHires, equals(4));
      expect(EventType.unknown, equals(0));
      expect(EventType.release, equals(3));
    });

    test('OptionFlags and MiceEvents match NCOPTION_*/NCMICE_*', () {
      expect(OptionFlags.inhibitSetlocale, equals(0x1));
      expect(OptionFlags.suppressBanners, equals(0x20));
      expect(OptionFlags.noAlternateScreen, equals(0x40));
      expect(OptionFlags.drainInput, equals(0x100));
      expect(MiceEvents.noEvents, equals(0));
      expect(MiceEvents.allEvents, equals(7));
    });

    test('PixelImple maps values to names', () {
      expect(PixelImple.fromValue(0), equals('none'));
      expect(PixelImple.fromValue(3), equals('iTerm2'));
      expect(PixelImple.kittySelfref.name, equals('kittySelfref'));
      expect(() => PixelImple.fromValue(7), throwsRangeError);
    });

    test('Sequences box strings have one rune per box part', () {
      for (final boxen in [
        Sequences.boxlightw,
        Sequences.boxheavyw,
        Sequences.boxroundw,
        Sequences.boxdoublew,
        Sequences.boxasciiw,
      ]) {
        expect(boxen.runes.length, equals(6), reason: boxen);
      }
      expect(Sequences.boxouterw.runes.length, equals(8));
    });
  });
}
