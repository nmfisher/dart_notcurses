import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Child-plane round-trip coverage. The cocoon_console notcurses backend uses
// child planes (one per Panel / BackendSurface) rather than the standard
// plane for its side-panels. cell_styling_test proves the plane-styling APIs
// round-trip on the STANDARD plane; these tests prove the same behavior on
// child planes, and — crucially — that a child plane's putStrYX also
// silently drops writes containing embedded SGR, which is why any surface
// callable that emits SGR-styled text (e.g. `screen.colorize(...)`) must
// strip the SGR at the boundary the way `NotcursesBackendSurface.putAt` now
// does. Without these, the surface path could regress into re-embedding SGR
// and the panel would silently render blank again.

void main() {
  group(
    'child plane',
    () {
      test('setFgRGB + putStrYX round-trips through atYX', () async {
        await withNotcurses((nc, std) {
          final child = std.create(
            PlaneOptions(y: 0, x: 0, rows: 3, cols: 10, name: 'child'),
          );
          expect(child, isNotNull);
          try {
            child!.setFgRGB(0xcd0000); // basic red
            child.putStrYX(0, 0, 'X');
            final c = child.atYX(0, 0);
            expect(c, isNotNull);
            expect(c!.egc, 'X');
            expect((c.channels >> 32) & 0xFFFFFF, 0xcd0000,
                reason: 'plane fg should land on the written cell');
          } finally {
            child?.destroy();
          }
        });
      });

      test('setBgRGB + putStrYX round-trips through atYX', () async {
        await withNotcurses((nc, std) {
          final child = std.create(
            PlaneOptions(y: 0, x: 0, rows: 3, cols: 10, name: 'child'),
          );
          expect(child, isNotNull);
          try {
            child!.setBgRGB(0x0000ee); // basic blue
            child.putStrYX(0, 0, 'Y');
            final c = child.atYX(0, 0);
            expect(c, isNotNull);
            expect(c!.egc, 'Y');
            expect(c.channels & 0xFFFFFF, 0x0000ee);
          } finally {
            child?.destroy();
          }
        });
      });

      test('setStyles bold round-trips through atYX', () async {
        await withNotcurses((nc, std) {
          final child = std.create(
            PlaneOptions(y: 0, x: 0, rows: 3, cols: 10, name: 'child'),
          );
          expect(child, isNotNull);
          try {
            child!.setStyles(Style.bold);
            child.putStrYX(0, 0, 'Z');
            final c = child.atYX(0, 0);
            expect(c, isNotNull);
            expect(c!.stylemask & Style.bold, Style.bold);
          } finally {
            child?.destroy();
          }
        });
      });

      test('putStrYX with embedded SGR is silently dropped (same as std plane)',
          () async {
        // The bug that made panels invisible: NotcursesBackendSurface.putAt
        // used to pass SGR-embedded text (`\x1b[36m...\x1b[0m`) straight to
        // the child plane's putStrYX. Same swallow as the standard plane —
        // both the escape bytes and the surrounding text vanish. If this
        // ever changes (child planes start honoring embedded SGR, or start
        // literalizing it), revisit `_emitSgrStyled` / `_PlaneSgrSink` in
        // cocoon_console — the workaround may be redundant or need updating.
        await withNotcurses((nc, std) {
          final child = std.create(
            PlaneOptions(y: 0, x: 0, rows: 3, cols: 10, name: 'child'),
          );
          expect(child, isNotNull);
          try {
            child!.putStrYX(0, 0, '\x1b[31mR\x1b[0m');
            final c = child.atYX(0, 0);
            expect(c, isNotNull);
            expect(c!.egc, isEmpty,
                reason: 'child plane swallows the whole write; the surface '
                    'code path must strip SGR before hitting putStrYX');
          } finally {
            child?.destroy();
          }
        });
      });
    },
    skip: !notcursesSupported
        ? 'needs a controlling TTY (notcurses opens /dev/tty)'
        : false,
  );
}
