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

  group('GC finalizer backstop', () {
    // Churn Dart allocations to give the GC a reason to run. Finalizer
    // execution is not deterministic; these tests prove the finalizer path
    // cannot crash the process (a wrong detach/double-free would abort).
    void churn() {
      var sink = 0;
      for (var i = 0; i < 50; i++) {
        sink += List<int>.generate(64 * 1024, (j) => j).length;
      }
      expect(sink, greaterThan(0));
    }

    test('undisposed Keys and Cells are reclaimed without crashing', () {
      for (var i = 0; i < 500; i++) {
        Key();
        final c = Cell.init();
        c.setStyles(Style.bold);
      }
      churn();
      // Mixed: explicitly destroyed objects must be detached from the
      // finalizer (a missed detach would double-free on a later GC).
      for (var i = 0; i < 500; i++) {
        Key().destroy();
        Cell.init().destroy();
      }
      churn();
    });

    test('destroy after finalizer attach stays idempotent', () {
      final k = Key();
      final c = Cell.init();
      k.destroy();
      c.destroy();
      expect(k.destroy, returnsNormally);
      expect(c.destroy, returnsNormally);
      churn();
    });
  }, skip: skip);
}
