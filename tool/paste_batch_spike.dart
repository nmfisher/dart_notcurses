// Phase 6 regression diagnostic: capture every record the BATCHED pump delivers
// during a paste, to determine whether NCKEY_PASTE_BEGIN/_END markers arrive
// through the new ring-queue + drain path (they do through the old per-event
// getNonBlocking-from-Dart path, proven by tool/paste_spike.dart).
//
// This mirrors paste_spike.dart but consumes input via NotcursesInputPump
// (startInputPump + onBatchStart + events) — the EXACT live path the production
// NotcursesInputBackend uses post-Phase-6 — instead of polling getNonBlocking
// from the main isolate. If markers are present here, the regression is in
// notcurses_input_backend.dart; if they're absent here but present in the old
// spike, the regression is in the batched pump (input_pump.c / _drain).
//
// Run from a real terminal:
//   dart run packages/dart_notcurses/tool/paste_batch_spike.dart
// Flow: press SPACE to arm -> paste a MULTI-LINE snippet -> press Enter.
// Look for NCKEY_PASTE_BEGIN / NCKEY_PASTE_END around the content, and whether
// embedded newlines arrive as LF (0x0a) or NCKEY_ENTER.
//
// Teardown ordering (the previous version froze the terminal): the pump's
// event listener ONLY signals a Completer; it never touches nc/pump. The main
// loop awaits that signal, then stops the PUMP FIRST (pthread_join, so the
// pump thread is no longer touching the notcurses context), THEN stops
// notcurses. Everything is in try/finally so bracketed-paste mode and the
// terminal state are always restored, even on Ctrl-C or a thrown error.
import 'dart:async';
import 'dart:io';

import 'package:dart_notcurses/dart_notcurses.dart';

Future<void> main() async {
  final nc = NotCurses(CursesOptions(
    loglevel: LogLevel.silent,
    flags: OptionFlags.suppressBanners,
  ));
  if (nc.notInitialized) {
    stderr.writeln('notcurses init failed');
    exit(1);
  }

  final events = <String>[];
  final done = Completer<void>();
  final plane = nc.stdplane();
  final clock = Stopwatch()..start();
  var armed = false;
  var captured = 0;
  var lastShort = '';
  var lastRender = 0;
  int? prevMicros;

  // Ctrl-C: signal completion (do NOT tear down here — the main loop does it).
  ProcessSignal.sigint.watch().listen((_) {
    if (!done.isCompleted) {
      events.add('-- SIGINT --');
      done.complete();
    }
  });

  NotcursesInputPump? pump;
  StreamSubscription<PumpedInput>? sub;

  try {
    // Enable bracketed paste exactly as production does (notcurses has no API).
    nc.writeRawToTty('\x1b[?2004h');
    _renderStatus(plane, 'press SPACE to arm', count: 0, last: '(draining startup)');

    pump = nc.startInputPump();
    pump.onBatchStart = (int n) {
      if (!armed) return; // discard startup junk pre-arm
      events.add('-- batch start: $n record(s) --');
    };
    sub = pump.events.listen((p) {
      final id = p.id;
      if (!armed) {
        // SPACE arms capture; everything before is startup junk.
        if (id == 0x20) {
          armed = true;
          prevMicros = clock.elapsedMicroseconds;
          _renderStatus(plane, 'PASTE a multi-line snippet, then Enter',
              count: 0, last: '(armed)');
        }
        return;
      }
      final now = clock.elapsedMicroseconds;
      final gap = prevMicros == null ? 0 : now - prevMicros!;
      prevMicros = now;
      final note = (id == 0x0a)
          ? '  <-- LF'
          : (id == NcKey.pasteBegin)
              ? '  <-- PASTE_BEGIN'
              : (id == NcKey.pasteEnd)
                  ? '  <-- PASTE_END'
                  : (id == NcKey.enter)
                      ? '  <-- NCKEY_ENTER'
                      : '';
      events.add(
        'gap=${gap}us id=$id ${_printable(id)} mod=${p.modifiers}$note',
      );
      captured++;
      lastShort = 'gap=${gap}us ${_printable(id)} ($captured)';
      final ms = DateTime.now().millisecondsSinceEpoch;
      if (ms - lastRender >= 30) {
        _renderStatus(plane, 'PASTE a multi-line snippet, then Enter',
            count: captured, last: lastShort);
        lastRender = ms;
      }
      if (id == NcKey.enter || id == 0x0a) {
        // Signal the main loop to tear down. Do NOT call nc/pump here.
        if (!done.isCompleted) done.complete();
      }
    });

    // Wait (with a timeout) for the user to finish, keeping the process alive
    // so the pump's async listener can fire.
    await done.future.timeout(const Duration(minutes: 5), onTimeout: () {
      events.add('-- TIMEOUT (5 min) --');
    });
  } finally {
    // Order matters: stop the PUMP first (joins its thread so it's no longer
    // touching the notcurses context), THEN stop notcurses, THEN restore the
    // terminal. Each step is guarded so one failure can't prevent the rest.
    try {
      sub?.cancel();
    } catch (_) {}
    try {
      pump?.stop();
    } catch (_) {}
    try {
      nc.stop();
    } catch (_) {}
    // Restore the terminal even if something above threw.
    try {
      // nc.stop() already restored blocking mode, but re-disable bracketed
      // paste in case stop() didn't run cleanly.
      stderr.writeln('\x1b[?2004l');
    } catch (_) {}

    stderr.writeln('');
    stderr.writeln('=== batched paste spike: ${events.length} lines ===');
    for (final e in events) {
      stderr.writeln(e);
    }
    stderr.writeln('=== end ===');
  }
}

String _printable(int id) {
  if (id >= 0x20 && id < 0x7f) return "'${String.fromCharCode(id)}'";
  if (id == 0x1b) return "'ESC'";
  if (id == 0x0a) return "'LF'";
  if (id == NcKey.enter) return "'NCKEY_ENTER'";
  if (id == NcKey.pasteBegin) return "'NCKEY_PASTE_BEGIN'";
  if (id == NcKey.pasteEnd) return "'NCKEY_PASTE_END'";
  if (id == NcKey.up) return "'NCKEY_UP'";
  if (id == NcKey.down) return "'NCKEY_DOWN'";
  return '0x${id.toRadixString(16)}';
}

void _renderStatus(Plane plane, String status,
    {required int count, required String last}) {
  plane.erase();
  plane.putStrYX(0, 0, 'Batched-paste spike (Phase 6 pump path)');
  plane.putStrYX(2, 0, status);
  plane.putStrYX(4, 0, 'captured: $count events');
  plane.putStrYX(5, 0, 'last: $last');
}
