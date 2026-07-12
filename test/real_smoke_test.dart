import 'package:test/test.dart';

import 'harness.dart';

void main() {
  group(
    'notcurses (real terminal)',
    () {
      test('inits and exposes a sized standard plane', () async {
        await withNotcurses((nc, std) {
          expect(nc.initialized, isTrue);
          final d = std.dimyx();
          expect(d.y, greaterThan(0));
          expect(d.x, greaterThan(0));
        });
      });

      test('putStrYX round-trips through atYX', () async {
        await withNotcurses((nc, std) {
          std.putStrYX(0, 0, 'hi');
          final cell = std.atYX(0, 0);
          expect(cell, isNotNull);
          expect(cell!.egc, startsWith('h'));
        });
      });

      test('refresh re-emits the current frame without error', () async {
        await withNotcurses((nc, std) {
          std.putStrYX(0, 0, 'x');
          expect(nc.render(), isTrue);
          // A no-change refresh (replay of the last rasterized frame) should
          // succeed — this is the recovery path for dropped terminal cells.
          expect(nc.refresh(), isTrue);
        });
      });
    },
    skip: !notcursesSupported ? 'needs a controlling TTY (notcurses opens /dev/tty)' : false,
  );
}
