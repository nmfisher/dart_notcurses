// ignore_for_file: library_prefixes
import 'dart:ffi' as ffi;
import 'dart:io' show File, FileMode;

import 'package:ffi/ffi.dart';

import './ffi/memory.dart';
import './ffi/notcurses_g.dart';
import './ffi/notcurses_g.dart' as nc;
import './ffi/notcurses_inline_g.dart' as ncInline;
import './key.dart';
import './plane.dart';
import './ptypes.dart';
import './shared.dart';

/// Configuration options to be used when create a new NotCurses intance
class CursesOptions {
  /// NcLogLevel options
  final int loglevel;
  final int marginT, marginR, marginB, marginL;
  final int flags;

  CursesOptions({
    this.loglevel = LogLevel.silent,
    this.marginT = 0,
    this.marginR = 0,
    this.marginB = 0,
    this.marginL = 0,
    this.flags = 0,
  });
}

class Version {
  final int major, minor, patch, tweak;
  const Version(this.major, this.minor, this.patch, this.tweak);

  @override
  String toString() {
    return '$major.$minor.$patch.$tweak';
  }
}

class Capabilities {
  final int colors;
  final bool utf8;
  final bool rgb;
  final bool canChangeColors;
  final bool halfblocks;
  final bool quadrants;
  final bool sextants;
  final bool braille;
  final bool octants;

  const Capabilities({
    this.colors = 0,
    this.utf8 = false,
    this.rgb = false,
    this.canChangeColors = false,
    this.halfblocks = false,
    this.quadrants = false,
    this.sextants = false,
    this.braille = false,
    this.octants = false,
  });

  @override
  String toString() {
    return '''
        colors: $colors
        utf8: $utf8
        canChangeColors: $canChangeColors
        halfblocks: $halfblocks
        quadrants: $quadrants
        sextants: $sextants
        braille: $braille
        octants: $octants
      ''';
  }
}

// libc fdopen/fclose, looked up in-process (present in libc/libSystem). Used to
// target a specific output file (e.g. a PTY slave) instead of /dev/tty.
late final ffi.Pointer<FILE> Function(int fd, ffi.Pointer<ffi.Char> mode)
    _fdopenLookup = ffi.DynamicLibrary.process().lookupFunction<
        ffi.Pointer<FILE> Function(ffi.Int32, ffi.Pointer<ffi.Char>),
        ffi.Pointer<FILE> Function(int, ffi.Pointer<ffi.Char>)>('fdopen');

late final int Function(ffi.Pointer<FILE>) _fcloseLookup =
    ffi.DynamicLibrary.process().lookupFunction<
        ffi.Int32 Function(ffi.Pointer<FILE>),
        int Function(ffi.Pointer<FILE>)>('fclose');

ffi.Pointer<FILE> _fdopenFile(int fd, String mode) {
  final modePtr = mode.toNativeUtf8().cast<ffi.Char>();
  final p = _fdopenLookup(fd, modePtr);
  malloc.free(modePtr);
  return p;
}

// clock_gettime, looked up in-process. notcurses input deadlines are absolute
// CLOCK_MONOTONIC timespans, so building a relative timeout needs the current
// monotonic clock — wall-clock (DateTime) can jump on NTP/timezone changes and
// is unsafe for a deadline.
late final int Function(int clkId, ffi.Pointer<timespec> tp) _clockGettime =
    ffi.DynamicLibrary.process().lookupFunction<
        ffi.Int32 Function(ffi.Int32, ffi.Pointer<timespec>),
        int Function(int, ffi.Pointer<timespec>)>('clock_gettime');

// CLOCK_MONOTONIC. Identical value (1) on Linux glibc and macOS; the macro
// isn't exposed to Dart, so it's pinned here. (CLOCK_REALTIME is 0 on both.)
const int _clockMonotonic = 1;

/// Build an absolute CLOCK_MONOTONIC deadline [Duration] from now, for
/// notcurses input calls that take a `timespec*`. Returns `nullptr` when
/// [timeout] is null (meaning "block indefinitely" to notcurses_get). Caller
/// frees the pointer with the package allocator, or passes nullptr through
/// unchanged. On a clock read failure, degrades to an immediate deadline so
/// the call never blocks on a clock fault.
ffi.Pointer<timespec> monotonicDeadline(Duration? timeout) {
  if (timeout == null) return ffi.nullptr;
  final ts = allocator<timespec>();
  if (_clockGettime(_clockMonotonic, ts) != 0) {
    return ts
      ..ref.tv_sec = 0
      ..ref.tv_nsec = 0;
  }
  final totalNs = ts.ref.tv_sec * 1000000000 + ts.ref.tv_nsec + timeout.inMicroseconds * 1000;
  ts.ref.tv_sec = totalNs ~/ 1000000000;
  ts.ref.tv_nsec = totalNs.remainder(1000000000);
  return ts;
}

class NotCurses {
  late ffi.Pointer<notcurses> _ptr;
  bool _stopped = false;

  /// A FILE* we opened via fdopen (when constructed with an output fd), closed
  /// on [stop]. Null when notcurses owns the output (/dev/tty).
  ffi.Pointer<FILE>? _ownedFile;

  NotCurses([CursesOptions? opts]) : this._(opts, null);

  /// Initialize against [outFd] (fdopen'd to a FILE* and passed as
  /// notcurses_init's output file) instead of /dev/tty. Lets a caller render
  /// to a specific tty/file — notably a PTY slave in tests. The FILE* is
  /// closed by [stop].
  NotCurses.withOutputFd(int outFd, [CursesOptions? opts]) : this._(opts, outFd);

  NotCurses._(CursesOptions? opts, int? outFd) {
    final ffi.Pointer<notcurses_options> optPtr =
        opts == null ? ffi.nullptr : _makeOptionsPtr(opts);
    ffi.Pointer<FILE> fp;
    if (outFd != null) {
      final f = _fdopenFile(outFd, 'w');
      if (f == ffi.nullptr) {
        // Bad fd: init cannot proceed; leave the instance notInitialized.
        if (optPtr != ffi.nullptr) allocator.free(optPtr);
        _ptr = ffi.nullptr;
        return;
      }
      _ownedFile = f;
      fp = f;
    } else {
      fp = ffi.nullptr;
    }
    _ptr = nc.notcurses_init(optPtr, fp);
    if (optPtr != ffi.nullptr) {
      allocator.free(optPtr);
    }
    if (_ptr == ffi.nullptr && _ownedFile != null) {
      // Init failed: close the FILE* we fdopen'd, nobody else will.
      _fcloseLookup(_ownedFile!);
      _ownedFile = null;
    }
  }

  NotCurses.fromPtr(ffi.Pointer<notcurses> value) {
    _ptr = value;
  }

  NotCurses.core([CursesOptions? opts]) {
    final ffi.Pointer<notcurses_options> optPtr =
        opts == null ? ffi.nullptr : _makeOptionsPtr(opts);
    _ptr = nc.notcurses_core_init(optPtr, ffi.nullptr);
    if (optPtr != ffi.nullptr) {
      allocator.free(optPtr);
    }
  }

  ffi.Pointer<notcurses> get ptr => _ptr;

  ffi.Pointer<notcurses_options> _makeOptionsPtr(CursesOptions opts) {
    final opsPtr = allocator<notcurses_options>();
    final ref = opsPtr.ref;
    ref.termtype = ffi.nullptr; // TODO: need to resolve the FD
    ref.loglevel = opts.loglevel;
    ref.margin_t = opts.marginT;
    ref.margin_l = opts.marginL;
    ref.margin_b = opts.marginB;
    ref.margin_r = opts.marginR;
    ref.flags = opts.flags;
    return opsPtr;
  }

  /// Returns true if NotCurses was initialized without problems
  bool get initialized => _ptr != ffi.nullptr;

  /// Returns true if NotCurses was not initialized
  bool get notInitialized => _ptr == ffi.nullptr;

  /// Renders and rasterizes the standard pile in one shot. Blocking call.
  bool render() {
    return ncInline.notcurses_render(_ptr) == 0;
  }

  /// Destroy a Notcurses context. If this context owns its output FILE*
  /// (constructed via [NotCurses.withOutputFd]), it is closed here.
  /// Safe to call more than once; only the first call tears the context down.
  bool stop() {
    if (_stopped) return true;
    _stopped = true;
    // notcurses_stop(NULL) is a harmless no-op, so a failed init is fine here.
    final ok = nc.notcurses_stop(_ptr) == 0;
    _ptr = ffi.nullptr;
    final f = _ownedFile;
    if (f != null && f != ffi.nullptr) {
      _fcloseLookup(f);
    }
    _ownedFile = null;
    return ok;
  }

  /// Get a reference to the standard plane (one matching our current idea of the
  /// terminal size) for this terminal. The standard plane always exists, and its
  /// origin is always at the uppermost, leftmost cell of the terminal.
  Plane stdplane() {
    return Plane.fromPtr(nc.notcurses_stdplane(_ptr));
  }

  /// Enable or disable the terminal's cursor, if supported, placing it at
  /// 'y', 'x'. Immediate effect (no need for a call to notcurses_render()).
  /// It is an error if 'y', 'x' lies outside the standard plane. Can be
  /// called while already visible to move the cursor.
  bool cursorEnable({int y = 0, int x = 0}) {
    return nc.notcurses_cursor_enable(_ptr, y, x) == 0;
  }

  /// Disable the hardware cursor. It is an error to call this while the
  /// cursor is already disabled.
  bool cursorDisable() {
    return nc.notcurses_cursor_disable(_ptr) == 0;
  }

  /// Lex a margin argument according to the standard Notcurses definition. There
  /// can be either a single number, which will define all margins equally, or
  /// there can be four numbers separated by commas.
  bool lexMargins(String margins, CursesOptions? opts) {
    final op = margins.toNativeUtf8().cast<ffi.Char>();
    final ffi.Pointer<notcurses_options> optPtr = opts == null ? ffi.nullptr : _makeOptionsPtr(opts);
    final rc = nc.notcurses_lex_margins(op, optPtr);
    allocator.free(op);
    if (optPtr != ffi.nullptr) {
      allocator.free(optPtr);
    }
    return rc == 0;
  }

  /// Enable mice events according to 'eventmask'; an eventmask of 0 will disable
  /// all mice tracking. On failure, -1 is returned. On success, 0 is returned, and
  /// mouse events will be published to notcurses_get().
  bool miceEnable(int miceEvents) {
    return nc.notcurses_mice_enable(_ptr, miceEvents) == 0;
  }

  /// Disable mouse events. Any events in the input queue can still be delivered.
  bool miceDisable() {
    return nc.notcurses_mice_enable(_ptr, MiceEvents.noEvents) == 0;
  }

  /// Read one input event. [timeout] of null blocks indefinitely; a finite
  /// [Duration] blocks up to that long (an absolute CLOCK_MONOTONIC deadline is
  /// built internally via [monotonicDeadline]); [Duration.zero] returns
  /// immediately. When [keyInfo] is false, only the event id is read and the
  /// returned value is null.
  ///
  /// [NcResult.result] is the event id, 0 on timeout, or a negative value on
  /// error; [NcResult.value] is the [Key] (null on error or when [keyInfo] is
  /// false). On timeout (id 0) an empty Key is still returned.
  NcResult<int, Key?> get({Duration? timeout, bool keyInfo = true}) {
    final ts = monotonicDeadline(timeout);
    if (!keyInfo) {
      final rc = nc.notcurses_get(_ptr, ts, ffi.nullptr);
      if (ts != ffi.nullptr) allocator.free(ts);
      return NcResult(rc, null);
    }
    final k = Key();
    final rc = nc.notcurses_get(_ptr, ts, k.ptr);
    if (ts != ffi.nullptr) allocator.free(ts);
    if (rc < 0) {
      k.destroy();
      return NcResult(rc, null);
    }
    return NcResult(rc, k);
  }

  /// Convenience: block indefinitely until an event arrives.
  NcResult<int, Key?> getBlocking() => get();

  /// Convenience: return immediately; 0 means no event was ready.
  NcResult<int, Key?> getNonBlocking({bool keyInfo = true}) =>
      get(timeout: Duration.zero, keyInfo: keyInfo);

  /// Acquire up to [max] input events at once. [NcResult.result] is the number
  /// read (negative on error, 0 on timeout); [NcResult.value] is the list of
  /// [Key]s, each owning a copy of its slot. [timeout] semantics match [get].
  NcResult<int, List<Key>> getVec({Duration? timeout, int max = 16}) {
    RangeError.checkNotNegative(max, 'max');
    final ts = monotonicDeadline(timeout);
    final buf = allocator<ncinput>(max == 0 ? 1 : max);
    final count = nc.notcurses_getvec(_ptr, ts, buf, max);
    if (ts != ffi.nullptr) allocator.free(ts);
    if (count < 0) {
      allocator.free(buf);
      return NcResult(count, <Key>[]);
    }
    final elemSize = ffi.sizeOf<ncinput>();
    final keys = <Key>[];
    for (var i = 0; i < count; i++) {
      // Copy the filled slot into its own owning Key (byte-copy is robust to
      // future struct-field additions; avoids a borrowed-pointer ownership mode).
      final dst = allocator<ncinput>();
      final src = (buf + i).cast<ffi.Uint8>();
      final dstBytes = dst.cast<ffi.Uint8>();
      for (var b = 0; b < elemSize; b++) {
        dstBytes[b] = src[b];
      }
      keys.add(Key.wrap(dst));
    }
    allocator.free(buf);
    return NcResult(count, keys);
  }

  /// Get a file descriptor suitable for input event poll()ing. When this
  /// descriptor becomes available, you can call notcurses_get_nblock(),
  /// and input ought be ready. This file descriptor is *not* necessarily
  /// the file descriptor associated with stdin (but it might be!).
  int getInputReadyFD() {
    return nc.notcurses_inputready_fd(_ptr);
  }

  /// Write a raw byte sequence directly to the controlling terminal
  /// (`/dev/tty`), bypassing notcurses' retained-mode output. notcurses
  /// owns its output `FILE*` and exposes no raw-write API, and writing to
  /// `stdout` interleaves badly with notcurses render output — so we open
  /// `/dev/tty` directly, the same pattern the test harness uses to emit
  /// XTMODKEYS undo sequences.
  ///
  /// Used for terminal mode toggles that have no notcurses API, such as
  /// bracketed paste (`ESC[?2004h` / `ESC[?2004l`). Silently does nothing
  /// when there is no controlling terminal.
  void writeRawToTty(String s) {
    try {
      final tty = File('/dev/tty').openSync(mode: FileMode.writeOnlyAppend);
      tty.writeStringSync(s);
      tty.closeSync();
    } catch (_) {
      // No controlling terminal (e.g. running under a pipe or in CI).
    }
  }

  /// Restore signals originating from the terminal's line discipline, i.e.
  /// SIGINT (^C), SIGQUIT (^\), and SIGTSTP (^Z), if disabled.
  int lineSigsEnable() {
    return nc.notcurses_linesigs_enable(_ptr);
  }

  // Disable signals originating from the terminal's line discipline, i.e.
  // SIGINT (^C), SIGQUIT (^\), and SIGTSTP (^Z). They are enabled by default.
  int lineSigsDisable() {
    return nc.notcurses_linesigs_disable(_ptr);
  }

  /// Cannot be inline, as we want to get the versions of the actual Notcurses
  /// library we loaded, not what we compile against.
  Version version() {
    return using<Version>((Arena alloc) {
      final major = alloc<ffi.Int>();
      final minor = alloc<ffi.Int>();
      final patch = alloc<ffi.Int>();
      final tweak = alloc<ffi.Int>();
      nc.notcurses_version_components(major, minor, patch, tweak);
      return Version(major.value, minor.value, patch.value, tweak.value);
    });
  }

  /// Get the default foreground color, if it is known. Returns -1 on error
  /// (unknown foreground). On success, returns 0, writing the RGB value to
  /// 'fg' (if non-NULL)
  int? defaultForeground() {
    return using<int?>((Arena alloc) {
      final ptr = alloc<ffi.Uint32>();
      final rc = nc.notcurses_default_foreground(_ptr, ptr);
      if (rc < 0) return null;
      return ptr.value;
    });
  }

  /// Get the default background color, if it is known. Returns -1 on error
  /// (unknown background). On success, returns 0, writing the RGB value to
  /// 'bg' (if non-NULL) and setting 'bgtrans' high iff the background color
  /// is treated as transparent.
  int? defaultBackground() {
    return using<int?>((Arena alloc) {
      final ptr = alloc<ffi.Uint32>();
      final rc = nc.notcurses_default_background(_ptr, ptr);
      if (rc < 0) return null;
      return ptr.value;
    });
  }

  /// Returns the name (and sometimes version) of the terminal, as Notcurses
  /// has been best able to determine.
  String? detectTerminal() {
    final rc = nc.notcurses_detected_terminal(_ptr);
    if (rc == ffi.nullptr) return null;
    final value = rc.cast<Utf8>().toDartString();
    allocator.free(rc);
    return value;
  }

  /// Returns a 16-bit bitmask of supported curses-style attributes
  /// (NCSTYLE_UNDERLINE, NCSTYLE_BOLD, etc.) The attribute is only
  /// indicated as supported if the terminal can support it together with color.
  /// For more information, see the "ncv" capability in terminfo(5).
  int supportedStyles() {
    return nc.notcurses_supported_styles(_ptr);
  }

  /// Returns the number of simultaneous colors claimed to be supported, or 1 if
  /// there is no color support. Note that several terminal emulators advertise
  /// more colors than they actually support, downsampling internally.
  int paletteSize() {
    return nc.notcurses_palette_size(_ptr);
  }

  /// Returns capabilities, derived from terminfo, environment variables, and queries
  Capabilities capabilities() {
    final capPtr = nc.notcurses_capabilities(_ptr);
    final cpr = capPtr.ref;

    return Capabilities(
      colors: cpr.colors,
      utf8: cpr.utf8,
      rgb: cpr.rgb,
      canChangeColors: cpr.can_change_colors,
      halfblocks: cpr.halfblocks,
      quadrants: cpr.quadrants,
      sextants: cpr.sextants,
      braille: cpr.braille,
      octants: cpr.octants,
    );
  }

  /// Can we emit 24-bit, three-channel RGB foregrounds and backgrounds?
  bool canTrueColor() {
    return ncInline.notcurses_cantruecolor(_ptr);
  }

  /// Can we fade? Fading requires either the "rgb" or "ccc" terminfo capability.
  bool canFade() {
    return ncInline.notcurses_canfade(_ptr);
  }

  /// Can we set the "hardware" palette? Requires the "ccc" terminfo capability,
  /// and that the number of colors supported is at least the size of our
  /// ncpalette structure.
  bool canChangeColors() {
    return ncInline.notcurses_canchangecolor(_ptr);
  }

  /// Can we load images? This requires being built against FFmpeg/OIIO.
  bool canOpenImages() {
    return nc.notcurses_canopen_images(_ptr);
  }

  /// Can we load videos? This requires being built against FFmpeg.
  bool canOpenVideos() {
    return nc.notcurses_canopen_videos(_ptr);
  }

  /// Is our encoding UTF-8? Requires LANG being set to a UTF8 locale.
  bool canUtf8() {
    return ncInline.notcurses_canutf8(_ptr);
  }

  // Can we reliably use Unicode halfblocks? Any Unicode implementation can.
  bool canHalfBlock() {
    return ncInline.notcurses_canhalfblock(_ptr);
  }

  /// Can we reliably use Unicode quadrants?
  bool canQuadrant() {
    return ncInline.notcurses_canquadrant(_ptr);
  }

  /// Can we reliably use Unicode 13 sextants?
  bool canSextant() {
    return ncInline.notcurses_cansextant(_ptr);
  }

  /// Can we reliably use Unicode Braille?
  bool canBraille() {
    return ncInline.notcurses_canbraille(_ptr);
  }

  /// Can we blit pixel-accurate bitmaps?
  bool canPixel() {
    return ncInline.notcurses_canpixel(_ptr);
  }

  /// Can we reliably use Unicode 16 octants?
  bool canOctant() {
    return ncInline.notcurses_canoctant(_ptr);
  }

  /// Can we blit pixel-accurate bitmaps?
  /// bitmap support. if we support bitmaps, pixel_implementation will be a
  /// value other than NCPIXEL_NONE.
  int checkPixelSupport() {
    return nc.notcurses_check_pixel_support(_ptr);
  }

  /// input functions like notcurses_get() return ucs32-encoded uint32_t. convert
  /// a series of uint32_t to utf8. result must be at least 4 bytes per input
  /// uint32_t (6 bytes per uint32_t will future-proof against Unicode expansion).
  /// the number of bytes used is returned, or -1 if passed illegal ucs32, or too
  /// small of a buffer.
  String ucsToUtf8(int ucs) {
    const buflen = 5; // up to 4 UTF-8 bytes per codepoint, plus NUL
    final ucsp = allocator<ffi.Uint32>();
    ucsp.value = ucs;
    final resultbuf = allocator<ffi.UnsignedChar>(buflen);
    final rc = nc.notcurses_ucs32_to_utf8(ucsp, 1, resultbuf, buflen);
    final utf8 = rc < 0 ? '' : resultbuf.cast<Utf8>().toDartString(length: rc);

    allocator.free(resultbuf);
    allocator.free(ucsp);
    return utf8;
  }
}
