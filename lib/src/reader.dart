import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import './channels.dart';
import './ffi/memory.dart';
import './ffi/notcurses_g.dart';
import './ffi/notcurses_g.dart' as nc;
import './key.dart';
import './plane.dart';

class ReaderOptions {
  Channels channels;

  /// StyleMask
  int attrWord;

  /// NcReaderOptions
  int flags;

  ReaderOptions(this.channels, this.attrWord, this.flags);
}

class Reader {
  ffi.Pointer<ncreader> _ptr;

  Reader._(this._ptr);

  /// ncreaders provide freeform input in a (possibly multiline) region, supporting
  /// optional readline keybindings. takes ownership of 'n', destroying it on any
  /// error (ncreader_destroy() otherwise destroys the ncplane).
  /// Returns null on failure — note the passed [plane] has been destroyed by
  /// the C library in that case and must not be used further.
  static Reader? create(Plane plane, ReaderOptions opts) {
    final op = allocator<ncreader_options>();
    op.ref
      ..tchannels = opts.channels.value
      ..tattrword = opts.attrWord
      ..flags = opts.flags;
    final ptr = nc.ncreader_create(plane.ptr, op);
    allocator.free(op);
    if (ptr == ffi.nullptr) {
      plane.markDestroyed();
      return null;
    }
    return Reader._(ptr);
  }

  /// Destroy the reader and return its final contents. Safe to call more
  /// than once; subsequent calls return ''.
  String destroy() {
    if (_ptr == ffi.nullptr) return '';
    final contents = allocator<ffi.Pointer<ffi.Char>>();
    nc.ncreader_destroy(_ptr, contents);
    _ptr = ffi.nullptr;
    var rc = '';
    if (contents.value != ffi.nullptr) {
      rc = contents.value.cast<Utf8>().toDartString();
      // ncreader_destroy heap-duplicates the input into *contents; the
      // caller owns (and must free) that buffer.
      allocator.free(contents.value);
    }
    allocator.free(contents);
    return rc;
  }

  /// empty the ncreader of any user input, and home the cursor.
  int clear() {
    return nc.ncreader_clear(_ptr);
  }

  Plane readerPlane() {
    return Plane.fromPtr(nc.ncreader_plane(_ptr));
  }

  /// Atttempt to move in the specified direction. Returns 0 if a move was
  /// successfully executed, -1 otherwise. Scrolling is taken into account.
  bool moveLeft() {
    return nc.ncreader_move_left(_ptr) == 0;
  }

  /// Atttempt to move in the specified direction. Returns 0 if a move was
  /// successfully executed, -1 otherwise. Scrolling is taken into account.
  bool moveRight() {
    return nc.ncreader_move_right(_ptr) == 0;
  }

  /// Atttempt to move in the specified direction. Returns 0 if a move was
  /// successfully executed, -1 otherwise. Scrolling is taken into account.
  bool moveUp() {
    return nc.ncreader_move_up(_ptr) == 0;
  }

  /// Atttempt to move in the specified direction. Returns 0 if a move was
  /// successfully executed, -1 otherwise. Scrolling is taken into account.
  bool moveDown() {
    return nc.ncreader_move_down(_ptr) == 0;
  }

  /// Destructively write the provided EGC to the current cursor location. Move
  /// the cursor as necessary, scrolling if applicable.
  bool writeEgc(String value) {
    final ugc = value.toNativeUtf8().cast<ffi.Char>();
    final rc = nc.ncreader_write_egc(_ptr, ugc);
    allocator.free(ugc);
    return rc == 0;
  }

  /// Offer the input to the ncreader. If it's relevant, this function returns
  /// true, and the input ought not be processed further. Almost all inputs
  /// are relevant to an ncreader, save synthesized ones.
  bool offerInput(Key key) {
    return nc.ncreader_offer_input(_ptr, key.ptr);
  }

  String contents() {
    final egc = nc.ncreader_contents(_ptr);
    if (egc == ffi.nullptr) return '';
    final rc = egc.cast<Utf8>().toDartString();
    // ncreader_contents returns a heap-allocated copy owned by the caller.
    allocator.free(egc);
    return rc;
  }
}
