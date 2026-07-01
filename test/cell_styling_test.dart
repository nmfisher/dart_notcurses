import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Cell styling: the plane's current fg/bg/styles are applied to cells written
// by putStrYX, and read back via atYX. fg occupies the high 32 bits of the
// 64-bit channels (rgb = bits 32..55); the stylemask is a separate Uint16.

void main() {
  group(
    'cell styling',
    () {
      test('setFgRGB8 is reflected in the written cell', () async {
        await withNotcurses((nc, std) {
          std.setFgRGB8(255, 0, 0); // red
          std.putStrYX(0, 0, 'R');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect((c!.channels >> 32) & 0xFFFFFF, 0xFF0000);
        });
      });

      test('setBgRGB8 is reflected in the written cell', () async {
        await withNotcurses((nc, std) {
          std.setBgRGB8(0, 0, 255); // blue
          std.putStrYX(0, 0, 'B');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.channels & 0xFFFFFF, 0x0000FF);
        });
      });

      test('setStyles bold is reflected in the stylemask', () async {
        await withNotcurses((nc, std) {
          std.setStyles(Style.bold);
          std.putStrYX(0, 0, 'X');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.stylemask & Style.bold, Style.bold);
        });
      });
    },
    skip: !notcursesSupported ? 'needs a controlling TTY (notcurses opens /dev/tty)' : false,
  );
}
