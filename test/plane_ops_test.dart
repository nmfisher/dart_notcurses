import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Plane operations that need a real notcurses context (controlling TTY).
void main() {
  final skip = notcursesSupported ? null : 'requires built lib + controlling TTY';

  group('plane ops (real terminal)', () {
    // Regression: putWstr* used to hand UTF-8 bytes to a wchar_t* API,
    // over-reading the heap and writing garbage glyphs.
    test('putWstrYX writes the string as wide chars', () async {
      await withNotcurses((nc, std) {
        final rc = std.putWstrYX(0, 0, 'hi');
        expect(rc, greaterThanOrEqualTo(0));
        expect(std.atYX(0, 0)?.egc, equals('h'));
        expect(std.atYX(0, 1)?.egc, equals('i'));
      });
    });

    test('putWstrYX handles non-ASCII codepoints', () async {
      await withNotcurses((nc, std) {
        final rc = std.putWstrYX(0, 0, '€!');
        expect(rc, greaterThanOrEqualTo(0));
        expect(std.atYX(0, 0)?.egc, equals('€'));
        expect(std.atYX(0, 1)?.egc, equals('!'));
      });
    });

    test('putWcUtf32 writes a single codepoint and rejects a lone surrogate', () async {
      await withNotcurses((nc, std) {
        std.cursorHome();
        final ok = std.putWcUtf32(0x41, 0); // 'A'
        expect(ok.result, greaterThanOrEqualTo(0));
        expect(std.atYX(0, 0)?.egc, equals('A'));

        // Regression: a lone high surrogate made C read past a 1-element
        // buffer; now the second slot is present and zeroed → clean error.
        std.cursorHome();
        final bad = std.putWcUtf32(0xD800, 0);
        expect(bad.result, equals(-1));
      });
    });

    // Regression: asRGBA computed its size from the out-params before the
    // call filled them, so it always returned an empty list.
    test('asRGBA returns pixel data for a painted region', () async {
      await withNotcurses((nc, std) {
        // NCBLIT_1x1's glyph set is the space; paint the region with spaces.
        std.putStrYX(0, 0, '  ');
        final rgba = std.asRGBA(Blitter.blit_1x1, 0, 0, 1, 2);
        expect(rgba, isNotNull);
        expect(rgba!.length, greaterThan(0));
      });
    });

    test('contents round-trips written text and is null out of bounds', () async {
      await withNotcurses((nc, std) {
        std.putStrYX(0, 0, 'hello');
        final text = std.contents(0, 0, 1, 5);
        expect(text, equals('hello'));
        expect(std.contents(999999, 0, 1, 1), isNull);
      });
    });

    // Regression: cursorMoveRel used to call the absolute-move C function.
    test('cursorMoveRel moves relative to the current position', () async {
      await withNotcurses((nc, std) {
        expect(std.cursorMoveYX(2, 3), isTrue);
        expect(std.cursorMoveRel(1, 1), isTrue);
        final pos = std.cursorYX();
        expect([pos.y, pos.x], equals([3, 4]));
      });
    });

    // Regression: mergeDown*/setName returned true on FAILURE (!= 0).
    test('mergeDownSimple and setName report success as true', () async {
      await withNotcurses((nc, std) {
        final child = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 10));
        expect(child, isNotNull);
        try {
          child!.putStrYX(0, 0, 'm');
          expect(child.mergeDownSimple(std), isTrue);
          expect(child.setName('mergesrc'), isTrue);
          expect(child.name(), equals('mergesrc'));
        } finally {
          child!.destroy();
        }
      });
    });

    test('dup duplicates the receiving plane', () async {
      await withNotcurses((nc, std) {
        final child = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 8));
        expect(child, isNotNull);
        child!.putStrYX(0, 0, 'd');
        final copy = child.dup();
        try {
          final dim = copy.dimyx();
          expect([dim.y, dim.x], equals([2, 8]));
          expect(copy.atYX(0, 0)?.egc, equals('d'));
        } finally {
          copy.destroy();
          child.destroy();
        }
      });
    });

    test('plane destroy is idempotent through the wrapper', () async {
      await withNotcurses((nc, std) {
        final child = std.create(PlaneOptions(y: 0, x: 0, rows: 1, cols: 1));
        expect(child, isNotNull);
        child!.destroy();
        expect(child.destroyed, isTrue);
        expect(child.destroy, returnsNormally);
      });
    });

    test('plane wrappers are canonical per ncplane', () async {
      await withNotcurses((nc, std) {
        expect(identical(nc.stdplane(), nc.stdplane()), isTrue);
        final child = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 2));
        expect(child, isNotNull);
        expect(identical(child, Plane.fromPtr(child!.ptr)), isTrue);
        child.destroy();
      });
    });

    test('destroy through one alias is visible through the others', () async {
      await withNotcurses((nc, std) {
        final child = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 2));
        final alias = Plane.fromPtr(child!.ptr);
        child.destroy();
        expect(alias.destroyed, isTrue);
        expect(alias.destroy, returnsNormally);
      });
    });

    test('loaded cells release against their loading plane automatically', () async {
      await withNotcurses((nc, std) {
        for (var i = 0; i < 100; i++) {
          final res = std.loadCell('x');
          expect(res.result, greaterThan(0));
          res.value!.destroy(); // no plane argument: auto-release on loader
        }
        expect(std.putStrYX(0, 0, 'ok'), greaterThan(0));
      });
    });

    test('releasing a cell against the wrong plane throws', () async {
      await withNotcurses((nc, std) {
        final other = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 2));
        final cell = std.loadCell('x').value!;
        expect(() => cell.destroy(other), throwsArgumentError);
        cell.destroy(std); // matching plane is fine
        other!.destroy();
      });
    });

    test('cell destroy after its plane is gone skips the pool release', () async {
      await withNotcurses((nc, std) {
        final plane = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 2));
        final cell = plane!.loadCell('x').value!;
        plane.destroy();
        expect(cell.destroy, returnsNormally);
      });
    });

    // The resize callback is bridged via NativeCallable.isolateLocal; this
    // covers registration + the lifetime path (the callable is closed on
    // destroy without crashing). Firing on an actual terminal resize needs a
    // real window/PTY resize and isn't automatable here.
    test('resize callback registers and tears down cleanly', () async {
      await withNotcurses((nc, std) {
        final child = std.create(
          PlaneOptions(y: 0, x: 0, rows: 2, cols: 4),
          onResize: (_) => true, // firing needs a real terminal resize (manual)
        );
        expect(child, isNotNull);
        expect(nc.render(), isTrue);

        // Swap the callback (closes the previous callable).
        child!.setResizeCallback((_) => true);
        expect(nc.render(), isTrue);

        // Clear it (sets nullptr, closes the callable).
        child.setResizeCallback(null);
        expect(nc.render(), isTrue);

        // Destroy closes any registered callable; must not crash or double-free.
        child.destroy();
        expect(child.destroyed, isTrue);
      });
    });

    test('create/destroy loop leaves the context usable', () async {
      await withNotcurses((nc, std) {
        for (var i = 0; i < 100; i++) {
          final p = std.create(PlaneOptions(y: 0, x: 0, rows: 2, cols: 2));
          expect(p, isNotNull);
          p!.destroy();
        }
        expect(std.putStrYX(0, 0, 'ok'), greaterThan(0));
      });
    });

    // Regression: buflen was passed as 1, so anything non-ASCII silently
    // returned '' (and leaked a C-side buffer).
    test('ucsToUtf8 converts ASCII and multibyte codepoints', () async {
      await withNotcurses((nc, std) {
        expect(nc.ucsToUtf8(0x41), equals('A'));
        expect(nc.ucsToUtf8(0x20AC), equals('€'));
      });
    });

    // Regression: a second stop() used to double-free the notcurses struct.
    // withNotcurses calls stop() again in its finally block.
    test('stop is idempotent', () async {
      await withNotcurses((nc, std) {
        expect(nc.stop(), isTrue);
        expect(nc.stop(), isTrue);
      });
    });
  }, skip: skip);
}
