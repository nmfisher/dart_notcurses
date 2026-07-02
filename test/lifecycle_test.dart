import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Teardown safety that can be exercised without a terminal.
void main() {
  final skip = hasNotcursesLib ? null : 'notcurses merged library not built';

  group('Key lifecycle', () {
    test('fresh key is zeroed', () {
      final k = Key();
      expect(k.id, equals(0));
      expect(k.x, equals(0));
      expect(k.y, equals(0));
      expect(k.modifiers, equals(0));
      expect(k.utf8List.length, equals(5));
      expect(k.utf8List.every((b) => b == 0), isTrue);
      k.destroy();
    });

    test('utf8List bytes are unsigned', () {
      final k = Key();
      // No negative values even for high bytes (struct field is signed char).
      expect(k.utf8List.every((b) => b >= 0 && b <= 0xff), isTrue);
      k.destroy();
    });

    test('destroy is idempotent', () {
      final k = Key();
      k.destroy();
      expect(k.destroy, returnsNormally);
      expect(k.destroy, returnsNormally);
    });
  }, skip: skip);

  group('NotCurses init failure', () {
    // Regression: a bad output fd used to store a NULL FILE* and fclose(NULL)
    // on stop; now init fails cleanly and stop() is a safe no-op.
    test('withOutputFd on an invalid fd fails cleanly', () {
      final n = NotCurses.withOutputFd(987654321, CursesOptions(loglevel: LogLevel.silent));
      expect(n.notInitialized, isTrue);
      expect(n.stop(), isTrue);
      expect(n.stop(), isTrue);
    });
  }, skip: skip);
}
