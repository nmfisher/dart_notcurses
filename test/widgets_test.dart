import 'dart:ffi';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Menu / Plot / Reader smoke tests against a real terminal.
void main() {
  final skip = notcursesSupported ? null : 'requires built lib + controlling TTY';

  group('Menu (real terminal)', () {
    Menu buildMenu() {
      return Menu(
        [
          MenuSection('File', [
            MenuItem('open', 'Open', shortcutKey: 'o', shortcutModifier: KeyMod.ctrl),
            MenuItem('quit', 'Quit', shortcutKey: 'q', shortcutModifier: KeyMod.ctrl),
          ]),
        ],
        MenuOptions(),
      );
    }

    test('create succeeds on the standard plane', () async {
      await withNotcurses((nc, std) {
        final menu = buildMenu();
        expect(menu.create(std), isTrue);
        expect(menu.initialized, isTrue);
        expect(menu.plane().ptr, isNot(equals(std.ptr)));
        menu.destroy();
        expect(menu.initialized, isFalse);
      });
    });

    // Regression: destroy() used to free the ncmenu twice (heap corruption /
    // allocator abort on every teardown).
    test('destroy is safe and idempotent', () async {
      await withNotcurses((nc, std) {
        final menu = buildMenu();
        expect(menu.create(std), isTrue);
        menu.destroy();
        expect(menu.destroy, returnsNormally);
      });
    });

    test('create/destroy loop does not corrupt the heap', () async {
      await withNotcurses((nc, std) {
        for (var i = 0; i < 20; i++) {
          final menu = buildMenu();
          expect(menu.create(std), isTrue);
          menu.destroy();
        }
        expect(std.putStrYX(0, 0, 'ok'), greaterThan(0));
      });
    });

    test('isMenuHotkey matches a registered shortcut', () async {
      await withNotcurses((nc, std) {
        final menu = buildMenu();
        expect(menu.create(std), isTrue);
        final k = Key();
        k.ptr.ref.id = 'q'.runes.first;
        k.ptr.ref.modifiers = KeyMod.ctrl;
        expect(menu.isMenuHotkey(k), equals('quit'));
        k.destroy();
        menu.destroy();
      });
    });
  }, skip: skip);

  group('Plot (real terminal)', () {
    test('create, sample, destroy', () async {
      await withNotcurses((nc, std) {
        final pplane = std.create(PlaneOptions(y: 0, x: 0, rows: 6, cols: 30));
        expect(pplane, isNotNull);
        final plot = Plot.create(pplane!, PlotOptions(miny: 0, maxy: 100));
        expect(plot, isNotNull);
        expect(plot!.addSample(0, 25), equals(0));
        expect(plot.addSample(1, 75), equals(0));
        plot.destroy();
        expect(plot.destroy, returnsNormally);
      });
    });
  }, skip: skip);

  group('Reader (real terminal)', () {
    test('create, write, contents, destroy', () async {
      await withNotcurses((nc, std) {
        final rplane = std.create(PlaneOptions(y: 0, x: 0, rows: 1, cols: 20));
        expect(rplane, isNotNull);
        final reader = Reader.create(
          rplane!,
          ReaderOptions(Channels.zero(), 0, ReaderOptionsFlags.cursor),
        );
        expect(reader, isNotNull);
        expect(reader!.writeEgc('a'), isTrue);
        expect(reader.writeEgc('b'), isTrue);
        // Regression: contents() used to leak the C buffer on every call.
        expect(reader.contents(), equals('ab'));
        expect(reader.clear(), equals(0));
        expect(reader.writeEgc('z'), isTrue);
        final last = reader.destroy();
        expect(last, equals('z'));
        // Regression: second destroy used to run ncreader_destroy on a freed
        // pointer; now it is a no-op returning ''.
        expect(reader.destroy(), equals(''));
      });
    });
  }, skip: skip);
}
