// Spike: does notcurses 3.0.17 expose bracketed-paste markers in its key
// stream, or does it swallow them?
//
// notcurses has no API for DECSET 2004 (bracketed paste), so we enable it
// ourselves by writing `ESC[?2004h` to /dev/tty. Then we capture every key
// event into an in-memory buffer and dump the log to stderr AFTER
// notcurses_stop() restores blocking stdio (writing mid-paste throws EAGAIN
// — errno 35 — because notcurses sets the tty non-blocking and a paste burst
// overwhelms the output buffer).
//
// CRITICAL: capture is GATED on a Space keypress. Right after notcurses init
// the terminal replies to capability queries (DA2, XTVERSION, bracketed-paste
// echoes) and those replies leak as mis-parsed synthesized keys (a burst of
// NCKEY_UP/NCKEY_DOWN). The production input backend drains these with a
// startup window; this spike drains them by discarding everything until you
// press Space to arm. That isolates paste events from startup noise so the
// go/no-go is clean.
//
// Run from a real terminal:
//   dart run packages/dart_notcurses/tool/paste_spike.dart            # enabled
//   dart run packages/dart_notcurses/tool/paste_spike.dart --no-paste-mode  # baseline
// Flow: press SPACE to arm → paste a MULTI-LINE snippet (include a newline)
// → press Enter to finish. Compare enabled vs --no-paste-mode runs: the
// DIFFERENCE between them is exactly what bracketed-paste markers add.
//
// PASS (enabled run): recognizable boundary events around the content —
//   either raw char events spelling \e[200~ / \e[201~, or a stable synthesized
//   key id — AND embedded newlines survive as newline events (not Enter).
// FAIL: no boundary events around the content, or embedded newlines become
// Enter (submitting mid-paste), or markers leak as unbounded printable text.
//
// Outcome → PASS: build marker detection in notcurses_input_backend.dart
//          (Phase 4).  FAIL: patch the vendored notcurses C input parser.
import 'dart:io';

import 'package:dart_notcurses/dart_notcurses.dart';

bool _finished = false;

void main(List<String> args) {
  final pasteModeEnabled = !args.contains('--no-paste-mode');

  final nc = NotCurses(CursesOptions(
    loglevel: LogLevel.silent,
    flags: OptionFlags.suppressBanners,
  ));
  if (nc.notInitialized) {
    stderr.writeln('notcurses init failed');
    exit(1);
  }

  final events = <String>[];
  // SIGINT: still dump whatever we captured and restore the terminal.
  ProcessSignal.sigint.watch().listen((_) => _finish(nc, events, pasteModeEnabled));

  final plane = nc.stdplane();
  var armed = false;
  var lastRender = 0;
  var lastShort = '';

  // Monotonic clock for inter-event gaps (DateTime can jump on NTP/timezone
  // changes; Stopwatch is monotonic). Arm-time is recorded so the gap to the
  // first captured event is meaningful, and the previous-event timestamp is
  // updated on every captured event.
  final clock = Stopwatch()..start();
  int? prevEventMicros;

  try {
    if (pasteModeEnabled) {
      nc.writeRawToTty('\x1b[?2004h');
    }
    _renderStatus(plane, 'press SPACE to arm',
        paste: pasteModeEnabled, armed: false, count: 0, last: '(draining startup)');

    while (true) {
      final res = nc.getNonBlocking(keyInfo: true);
      final k = res.value;
      // result == 0 → timeout; < 0 → error. notcurses still hands back an
      // empty Key on timeout, so free it and skip (otherwise every idle tick
      // logs a bogus id=0 line that drowns out real input).
      if (k == null || res.result <= 0) {
        k?.destroy();
        sleep(const Duration(milliseconds: 4));
        continue;
      }
      final id = k.id;

      if (!armed) {
        // Drain startup junk until the user arms capture with Space (0x20).
        k.destroy();
        if (id == 0x20) {
          armed = true;
          prevEventMicros = clock.elapsedMicroseconds;
          _renderStatus(plane, 'PASTE a multi-line snippet, then Enter',
              paste: pasteModeEnabled, armed: true, count: 0, last: '(armed)');
        }
        continue;
      }

      // Gap since the previous captured event, in microseconds. For the first
      // event after arm this is the gap from the arm keypress — small if the
      // user pasted immediately. This is the signal that distinguishes a paste
      // (tight burst, gaps < ~5ms) from typing (gaps > ~50ms).
      final nowMicros = clock.elapsedMicroseconds;
      final gap = prevEventMicros == null ? 0 : nowMicros - prevEventMicros;
      prevEventMicros = nowMicros;

      final note = (id == 0x0a) ? '  <-- NEWLINE (LF)' : '';
      events.add(
        'gap=${gap}us id=$id ${_printable(id)} utf8=${k.utf8List} '
        'synth=${k.keySynthesizedP()} alt=${k.hasAlt()} ctrl=${k.hasCtrl()} '
        'mod=${k.modifiers} evtype=${k.evType}$note',
      );
      lastShort = 'gap=${gap}us ${_printable(id)} (${events.length})';

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastRender >= 30) {
        _renderStatus(plane, 'PASTE a multi-line snippet, then Enter',
            paste: pasteModeEnabled, armed: true, count: events.length, last: lastShort);
        lastRender = now;
      }

      final stop = id == NcKey.enter || id == 0x0a;
      k.destroy();
      if (stop) break;
    }
  } finally {
    _finish(nc, events, pasteModeEnabled);
  }
}

String _printable(int id) {
  if (id >= 0x20 && id < 0x7f) return "'${String.fromCharCode(id)}'";
  if (id == 0x1b) return "'ESC'";
  if (id == 0x0a) return "'LF'";
  if (id == NcKey.enter) return "'NCKEY_ENTER'";
  if (id == NcKey.up) return "'NCKEY_UP'";
  if (id == NcKey.down) return "'NCKEY_DOWN'";
  return '0x${id.toRadixString(16)}';
}

void _renderStatus(
  Plane plane,
  String status, {
  required bool paste,
  required bool armed,
  required int count,
  required String last,
}) {
  plane.erase();
  plane.putStrYX(0, 0, 'Bracketed-paste spike  (paste mode: ${paste ? "ON" : "OFF (--no-paste-mode)"})');
  plane.putStrYX(2, 0, status);
  plane.putStrYX(4, 0, 'captured: $count events');
  plane.putStrYX(5, 0, 'last: $last');
}

void _finish(NotCurses nc, List<String> events, bool pasteModeEnabled) {
  if (_finished) return;
  _finished = true;
  // Restore the terminal BEFORE writing the log: stop() returns the tty to
  // blocking mode so stderr writes can't throw EAGAIN.
  if (pasteModeEnabled) {
    nc.writeRawToTty('\x1b[?2004l');
  }
  nc.stop();
  stderr.writeln('');
  stderr.writeln('=== paste spike: ${events.length} events '
      '(paste mode ${pasteModeEnabled ? "ON" : "OFF"}) ===');
  for (final e in events) {
    stderr.writeln(e);
  }
  // Gap statistics to set the burst-detection threshold. The question: do
  // pasted events cluster tightly (small gaps) so a time-windowed join can
  // tell them apart from typing (large gaps)? Report max gap and the count of
  // gaps exceeding a few candidate thresholds so we can pick a window that
  // contains all paste events but no typing.
  final gaps = <int>[];
  for (final e in events) {
    final m = RegExp(r'gap=(\d+)us').firstMatch(e);
    if (m != null) gaps.add(int.parse(m.group(1)!));
  }
  if (gaps.isNotEmpty) {
    gaps.sort();
    final over5 = gaps.where((g) => g > 5000).length;
    final over10 = gaps.where((g) => g > 10000).length;
    final over20 = gaps.where((g) => g > 20000).length;
    final over40 = gaps.where((g) => g > 40000).length;
    stderr.writeln('');
    stderr.writeln('--- gap stats (${gaps.length} gaps) ---');
    stderr.writeln('  max gap: ${gaps.last}us');
    stderr.writeln('  median gap: ${gaps[gaps.length ~/ 2]}us');
    stderr.writeln('  >5ms: $over5   >10ms: $over10   >20ms: $over20   >40ms: $over40');
    stderr.writeln('  (a good join window sits above the paste cluster '
        'but below typing gaps)');
  }
  stderr.writeln('=== end ===');
}
