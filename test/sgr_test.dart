import 'package:test/test.dart';

import 'harness.dart';

// SGR pass-through (NOTCURSES_TICKETS T-07): does ncplane_putstr_yx interpret
// embedded SGR escapes ("\x1b[31m...\x1b[0m")? Confirmed answer: NO — and
// worse, the escape bytes AND the surrounding printable text ALL vanish; the
// cell is left in its initial (empty) state. This is why callers must strip
// SGR out and use plane-styling APIs directly (see cocoon_console's
// NotcursesBackend.writeText / _applySgr).
//
// The test asserts this negative behavior so any future notcurses change
// (embedding gets supported, or embedding starts literalizing rather than
// swallowing) will trip a red bar and force us to reconsider the workaround.

void main() {
  group(
    'SGR pass-through (T-07)',
    () {
      test('putStr silently drops writes containing embedded SGR', () async {
        await withNotcurses((nc, std) {
          std.putStrYX(0, 0, '\x1b[31mR\x1b[0m');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.egc, isEmpty,
              reason:
                  'notcurses swallows the whole write — neither the ESC bytes '
                  'nor the "R" reach the cell. If this ever changes, revisit '
                  'NotcursesBackend._applySgr in cocoon_console.');
        });
      });
    },
    skip: !notcursesSupported ? 'needs a controlling TTY (notcurses opens /dev/tty)' : false,
  );
}
