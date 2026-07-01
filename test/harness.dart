import 'dart:async';
import 'dart:io';

import 'package:dart_notcurses/dart_notcurses.dart';

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

String get _mergedLibPath => Platform.isMacOS
    ? '.dart_tool/lib/libnotcurses_merged.dylib'
    : '.dart_tool/lib/libnotcurses_merged.so';

/// Whether the static notcurses library (built by the hook) is present.
bool get hasNotcursesLib => File(_mergedLibPath).existsSync();

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

/// Initialize [NotCurses] against the controlling terminal, run [body], and
/// stop. Throws if init fails (e.g. no TTY).
Future<void> withNotcurses(
  FutureOr<void> Function(NotCurses nc, Plane std) body,
) async {
  final nc = NotCurses(CursesOptions(loglevel: LogLevel.silent));
  if (nc.notInitialized) {
    throw StateError('notcurses_init failed (is there a controlling TTY?)');
  }
  try {
    await body(nc, nc.stdplane());
  } finally {
    nc.stop();
  }
}
