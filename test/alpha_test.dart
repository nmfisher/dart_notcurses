import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Background alpha / transparency. This is the property behind the opaque
// overlay bug: a cell whose bg alpha is TRANSPARENT composites over what's
// beneath instead of painting an opaque background. bg alpha occupies bits
// 28..29 of the 64-bit channels (the low/bg half): channels & 0x30000000.

void main() {
  group(
    'background alpha',
    () {
      test('setBgAlpha(transparent) yields a transparent cell background', () async {
        await withNotcurses((nc, std) {
          std.setBgAlpha(Alpha.transparent);
          std.putStrYX(0, 0, 't');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.channels & 0x30000000, Alpha.transparent);
        });
      });

      test('setBgDefault yields an opaque cell background', () async {
        await withNotcurses((nc, std) {
          std.setBgDefault();
          std.putStrYX(0, 0, 'd');
          final c = std.atYX(0, 0);
          expect(c, isNotNull);
          expect(c!.channels & 0x30000000, Alpha.opaque);
        });
      });
    },
    skip: !notcursesSupported ? 'needs a controlling TTY (notcurses opens /dev/tty)' : false,
  );
}
