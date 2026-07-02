import 'dart:async';
import 'dart:io';

import 'package:dart_notcurses/dart_notcurses.dart';
import 'package:dart_notcurses/src/ffi/notcurses_inline_g.dart' as ncinline;

// Test harness for notcurses.
//
// notcurses_init requires a real TTY (with fp=NULL it opens /dev/tty, which
// only exists when the process has a controlling terminal). A headless PTY
// doesn't work: notcurses sends a multi-wave capability-query handshake
// (palette x256, default colors, kitty keyboard/graphics, sixel/pixel DA,
// geometry) and blocks on each response with no timeout — faithfully emulating
// a terminal to answer all of them is impractical. So tests run against the
// real terminal the test process is attached to (local dev, or CI under a
// pty/xvfb). Gate callers on [notcursesSupported].
//
// Note: init enters the alternate screen briefly; [stop] restores it.

bool? _libProbe;

/// Whether the notcurses code asset (built by the hook, resolved by the SDK
/// via @Native) is available: probe with a harmless pure-computation call.
bool get hasNotcursesLib {
  return _libProbe ??= () {
    try {
      ncinline.ncchannels_combine(0, 0);
      return true;
    } catch (_) {
      return false;
    }
  }();
}

/// Whether the process has a controlling terminal — the real condition
/// notcurses needs (it opens /dev/tty). `stdout.hasTerminal` is false under
/// `dart test` even when a controlling tty exists, so probe /dev/tty directly.
bool get hasControllingTty {
  try {
    File('/dev/tty').openSync(mode: FileMode.read).closeSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// notcurses is testable here when the lib is built and /dev/tty is openable.
bool get notcursesSupported => hasNotcursesLib && hasControllingTty;

/// Best-effort restoration of the controlling terminal's state.
///
/// Under `dart test`, the test process's stdout is a captured pipe, so
/// notcurses' RESTORATION sequences land in the captured stream while some
/// of its init-time state changes (cursor hide, kitty keyboard push) went
/// straight to /dev/tty during the capability handshake. The asymmetry
/// leaves the shell without a cursor after the suite. Write the inverse
/// sequences directly to the terminal; every sequence is idempotent and
/// harmless when the state is already correct.
void restoreTty() {
  try {
    final tty = File('/dev/tty').openSync(mode: FileMode.writeOnlyAppend);
    tty.writeStringSync(
      '\x1b[0m' // reset SGR attributes
      '\x1b[?25h' // show the cursor (DECTCEM)
      '\x1b[<u', // pop kitty keyboard protocol (no-op if unsupported/empty)
    );
    tty.closeSync();
  } catch (_) {
    // No controlling terminal — nothing to restore.
  }
}

/// Initialize [NotCurses] against the controlling terminal, run [body], and
/// stop. Throws if init fails (e.g. no TTY).
Future<void> withNotcurses(
  FutureOr<void> Function(NotCurses nc, Plane std) body,
) async {
  final nc = NotCurses(CursesOptions(loglevel: LogLevel.silent));
  if (nc.notInitialized) {
    // A failed init can still have mutated the terminal mid-handshake.
    restoreTty();
    throw StateError('notcurses_init failed (is there a controlling TTY?)');
  }
  try {
    await body(nc, nc.stdplane());
  } finally {
    nc.stop();
    restoreTty();
  }
}
