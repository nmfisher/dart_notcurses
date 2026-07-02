// ignore_for_file: library_prefixes
import 'dart:ffi';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:dart_notcurses/src/ffi/notcurses_g.dart' as nc;
import 'package:dart_notcurses/src/ffi/notcurses_inline_g.dart' as ncInline;
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  // With @Native bindings, symbols resolve on first call through the code
  // asset the build hook declares — so "the symbol is bound" is tested by
  // calling side-effect-free functions from each generated file.
  group('FFI symbols resolve', () {
    test('main bindings resolve (notcurses_version)', () {
      final v = nc.notcurses_version();
      expect(v, isNot(equals(nullptr)));
      expect(v.cast<Utf8>().toDartString(), startsWith('3.'));
    });

    test('inline bindings resolve (ncchannels_combine)', () {
      expect(ncInline.ncchannels_combine(0x123456, 0x654321),
          equals((0x123456 << 32) | 0x654321));
    });

    test('nckey predicates resolve and compute', () {
      expect(ncInline.nckey_mouse_p(NcKey.button1), isTrue);
      expect(ncInline.nckey_mouse_p(0x41), isFalse);
    });
  }, skip: hasNotcursesLib ? null : 'notcurses code asset not built');

  // Direct mode writes to the controlling terminal.
  group('Direct mode', () {
    late Direct direct;

    setUp(() {
      direct = Direct();
      expect(direct.initialized, isTrue, reason: 'ncdirect_init failed');
    });

    tearDown(() {
      expect(direct.stop(), isTrue);
      // Regression: stop() used to double-free on a second call.
      expect(direct.stop(), isTrue);
      restoreTty();
    });

    test('reports sane dimensions and palette', () {
      expect(direct.dimy(), greaterThan(0));
      expect(direct.dimx(), greaterThan(0));
      expect(direct.paletteSize(), greaterThan(0));
    });

    test('canOctant agrees with capabilities().octants', () {
      expect(direct.capabilities().octants, equals(direct.canOctant()));
    });

    test('putStr writes without error', () {
      expect(direct.putStr(''), greaterThanOrEqualTo(0));
    });
  }, skip: notcursesSupported ? null : 'requires built lib + controlling TTY');
}
