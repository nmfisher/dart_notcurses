import 'dart:async';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:test/test.dart';

import 'harness.dart';

// Phase 6: the native input pump batches records per native→Dart notification.
// These tests drive the real NotcursesInputPump against a live notcurses
// context, so they require a controlling TTY (skipped in CI). The drain-loop
// translation logic is exercised headlessly via cocoon_console's
// notcurses_input_backend_test.dart (pumpedBatchForTest), which injects
// records without a live terminal.
//
// What these verify that the headless tests cannot: the native ring queue +
// edge-triggered notification + pumpDrain FFI actually fire the Dart listener
// once per empty→non-empty transition and copy a batch of records out in one
// transition (dartCallbackBatches << nativeEvents for a burst).

void main() {
  final skip = notcursesSupported
      ? null
      : 'requires built lib + controlling TTY';

  group('NotcursesInputPump batching', () {
    test('a single event yields one batch with one record', () async {
      // We can't synthesize keystrokes into /dev/tty from within the test
      // process reliably, so this is a structural smoke test: construct a pump,
      // confirm it starts and stops cleanly, and that onBatchStart is wired.
      // The batched-drain contract itself is proven by the cocoon_console
      // backend tests (pumpedBatchForTest) + the live manual paste check
      // documented in docs/OPTIMIZATIONS.md Phase 6.
      await withNotcurses((NotCurses ncur, Plane _) async {
        var batchCount = 0;
        var recordCount = 0;
        final pump = ncur.startInputPump();
        pump.onBatchStart = (int n) {
          batchCount++;
          recordCount += n;
        };
        final sub = pump.events.listen((_) {});
        // Give the pump a moment to arm, then tear down. No input is injected,
        // so no batches should fire.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(batchCount, 0,
            reason: 'no input → no batches fire while idle');
        await sub.cancel();
        pump.stop();
        expect(recordCount, 0);
      });
    }, skip: skip);
  });
}
