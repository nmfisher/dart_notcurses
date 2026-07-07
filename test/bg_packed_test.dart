import 'package:test/test.dart';

import 'harness.dart';

// Cocoon's chat message bars set the plane background via the PACKED
// setBgRGB(hex) — a single uint32, lower 24 bits — driven by its SGR sink
// (basic bg codes 40/47 and truecolor 48;2;r;g;b all land on this call). The
// existing cell_styling_test covers setBgRGB8(r,g,b); this exercises the
// packed path (ncplane_set_bg_rgb), which is the one the bars actually use.
//
// If the background channel read back here is wrong, the packed binding is why
// the bars don't paint. fg lives in the high 32 bits of the 64-bit channels
// (rgb = bits 32..55); bg in the low 32 (rgb = bits 0..23). Run locally where
// a controlling TTY exists (`dart test test/bg_packed_test.dart`).

void main() {
  group(
    'packed setBgRGB / setFgRGB',
    () {
      test('setBgRGB(hex) sets the cell background', () async {
        await withNotcurses((nc, std) {
          expect(std.setBgRGB(0x0000FF), isTrue,
              reason: 'setBgRGB reports success'); // blue
          std.putStrYX(0, 0, 'B');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.channels & 0xFFFFFF, 0x0000FF,
              reason: 'packed setBgRGB must be stored on the written cell');
        });
      });

      test('setFgRGB(hex) sets the cell foreground', () async {
        await withNotcurses((nc, std) {
          expect(std.setFgRGB(0xFF0000), isTrue); // red
          std.putStrYX(0, 0, 'R');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect((c!.channels >> 32) & 0xFFFFFF, 0xFF0000,
              reason: 'packed setFgRGB must be stored on the written cell');
        });
      });

      test('fg + bg together across a multi-char run (the bar pattern)',
          () async {
        // Mirrors how cocoon paints a message bar: a foreground color over a
        // distinct background, written as a run of characters (the padded
        // bar). Every cell in the run must carry both channels — not just the
        // first.
        await withNotcurses((nc, std) {
          std.setFgRGB(0xFFFFFF); // white text
          std.setBgRGB(0x112233); // dark slate bg (non-zero => unambiguous)
          std.putStrYX(0, 0, 'hello');
          for (var i = 0; i < 5; i++) {
            final c = std.atYX(0, i);
            expect(c, isNotNull, reason: 'cell $i missing');
            expect((c!.channels >> 32) & 0xFFFFFF, 0xFFFFFF,
                reason: 'cell $i fg should be white');
            expect(c.channels & 0xFFFFFF, 0x112233,
                reason: 'cell $i bg should be the slate bar');
          }
        });
      });

      test('explicit black bg is distinct from the default (transparent) bg',
          () async {
        // The user-message bar uses bg=black (setBgRGB(0x000000)). If notcurses
        // treats explicit black the same as the "default"/transparent
        // background, the black bar never paints — the prime suspect for the
        // user-message bar not showing. Compare the two channels directly so
        // the assertion doesn't depend on a specific default-flag bit.
        await withNotcurses((nc, std) {
          std.setBgRGB(0x000000); // explicit black
          std.putStrYX(0, 0, 'X');
          final black = std.atYX(0, 0)!.channels & 0xFFFFFFFF;

          std.setBgDefault();
          std.putStrYX(0, 1, 'Y');
          final def = std.atYX(0, 1)!.channels & 0xFFFFFFFF;

          expect(black, isNot(equals(def)),
              reason:
                  'explicit black bg must differ from the transparent default');
        });
      });
    },
    skip: !notcursesSupported
        ? 'needs a controlling TTY (notcurses opens /dev/tty)'
        : false,
  );
}
