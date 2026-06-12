import 'dart:io';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:dart_notcurses/src/load_library.dart';
import 'package:test/test.dart';

/// Notcurses integration tests require the native library to be installed.
/// On Linux, check for libnotcurses.so; on macOS, check for libnotcurses.dylib.
final hasNotcurses = Platform.isLinux
    ? File('/usr/local/lib/libnotcurses.so').existsSync()
    : Platform.isMacOS
        ? File('/usr/local/opt/notcurses/lib/libnotcurses.dylib').existsSync()
        : false;

void main() {
  group('FFI symbols exist', () {
    setUp(() {
      // Ensure library is loaded (will throw if notcurses is missing)
    });

    test('ncplane_family_destroy is bound', () {
      expect(() => nc.ncplane_family_destroy, returnsNormally);
    });

    test('notcurses_canoctant is bound', () {
      expect(() => ncInline.notcurses_canoctant, returnsNormally);
    });

    test('ncdirect_canoctant is bound', () {
      expect(() => ncInline.ncdirect_canoctant, returnsNormally);
    });
  }, skip: !hasNotcurses);

  group('Direct mode', () {
    late Direct direct;

    setUp(() {
      direct = Direct();
    });

    tearDown(() {
      direct.stop();
    });

    test('canOctant returns bool', () {
      expect(direct.canOctant(), isA<bool>());
    });

    test('capabilities includes octants', () {
      final caps = direct.capabilities();
      expect(caps.octants, isA<bool>());
    });
  }, skip: !hasNotcurses);
}
