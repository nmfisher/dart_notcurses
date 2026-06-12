import 'dart:ffi';
import 'dart:io';

import './ffi/notcurses_g.dart';
import './ffi/notcurses_inline_g.dart';

DynamicLibrary? _mergedLib;
DynamicLibrary get _lib => _mergedLib ??= _openLibrary();

NcFfi? _ncffi;
NcFfi get nc => _ncffi ??= NcFfi(_lib);

NcFfiInline? _ncffiInline;
NcFfiInline get ncInline => _ncffiInline ??= NcFfiInline(_lib);

DynamicLibrary _openLibrary() {
  if (Platform.isLinux) {
    // The build hook compiles and links notcurses into a single merged
    // library at .dart_tool/lib/libnotcurses_merged.so.
    return DynamicLibrary.open('.dart_tool/lib/libnotcurses_merged.so');
  }
  if (Platform.isMacOS) {
    // The merged library is built relative to the package root (the CWD when
    // running via `dart run`). macOS's hardened runtime forbids dlopen of a
    // relative path, so resolve it to absolute first.
    return DynamicLibrary.open(
      File('.dart_tool/lib/libnotcurses_merged.dylib').absolute.path,
    );
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
