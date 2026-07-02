import 'dart:ffi' as ffi;

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  final libSkip = hasNotcursesLib ? null : 'notcurses code asset not built';
  // The get/getVec C calls need an initialized context (a controlling tty);
  // the deadline math does not.
  final ttySkip = notcursesSupported ? null : 'requires built lib + controlling TTY';

  group('monotonicDeadline', () {
    test('null timeout -> a zero-address pointer (block forever)', () {
      expect(monotonicDeadline(null).address, isZero);
    });

    test('finite timeout -> a deadline ~timeout in the future', () {
      // Absolute CLOCK_MONOTONIC: must be >= "now" and at most ~timeout ahead.
      final before = monotonicDeadline(Duration.zero).ref.tv_sec;
      final dl = monotonicDeadline(const Duration(seconds: 1)).ref;
      final after = monotonicDeadline(Duration.zero).ref.tv_sec;
      expect(dl.tv_sec, greaterThanOrEqualTo(before));
      expect(dl.tv_sec, lessThanOrEqualTo(after + 1));
      expect(dl.tv_sec - before, lessThanOrEqualTo(1));
      expect(ffi.nullptr.address, isZero); // keep the dart:ffi import meaningful
    });
  }, skip: libSkip);

  group('NotCurses input', () {
    // A zero timeout must return promptly — never block. The queue's contents
    // are environment-dependent (buffered events, EOF), so assert the return is
    // non-error rather than a specific empty-queue value.
    test('get with a zero timeout does not block', () {
      withNotcursesSync((nc) {
        final res = nc.get(timeout: Duration.zero);
        expect(res.result, greaterThanOrEqualTo(0));
        res.value?.destroy();
      });
    });

    test('getVec returns as many Keys as it reports read', () {
      withNotcursesSync((nc) {
        final res = nc.getVec(timeout: Duration.zero, max: 8);
        expect(res.result, greaterThanOrEqualTo(0));
        expect(res.value.length, equals(res.result));
        for (final k in res.value) {
          k.destroy();
        }
      });
    });

    test('get without keyInfo returns a null value', () {
      withNotcursesSync((nc) {
        final res = nc.get(timeout: Duration.zero, keyInfo: false);
        expect(res.value, isNull);
      });
    });
  }, skip: ttySkip);

  group('getVec argument validation', () {
    // RangeError fires before any C call, so no live context is required.
    test('rejects a negative max', () {
      final n = NotCurses(CursesOptions(loglevel: LogLevel.silent));
      try {
        expect(() => n.getVec(max: -1), throwsRangeError);
      } finally {
        n.stop();
      }
    });
  }, skip: libSkip);
}

// Synchronous variant of the TTY harness for input calls that don't await.
void withNotcursesSync(void Function(NotCurses nc) body) {
  final nc = NotCurses(CursesOptions(loglevel: LogLevel.silent));
  if (nc.notInitialized) {
    throw StateError('notcurses_init failed (is there a controlling TTY?)');
  }
  try {
    body(nc);
  } finally {
    nc.stop();
    restoreTty();
  }
}
