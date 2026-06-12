import 'dart:ffi';
import 'dart:io';

import './ffi/notcurses_g.dart';
import './ffi/notcurses_inline_g.dart';

final LibraryHandler openLibrary = LibraryHandler._();

NcFfi? _ncffi;
NcFfi get nc {
  return _ncffi ??= NcFfi(openLibrary.openNotcurses());
}

NcFfiInline? _ncffiInline;
NcFfiInline get ncInline {
  return _ncffiInline ??= NcFfiInline(openLibrary.openNotcursesInline());
}

// TODO: this is using the default directory path where Brew install on OSX.
// need to support ways to override this path.
// - sqlite add a method that receive the new path
class LibraryHandler {
  LibraryHandler._();

  static const _macPaths = [
    '/opt/homebrew/opt/notcurses/lib', // Apple Silicon
    '/usr/local/opt/notcurses/lib', // Intel
  ];

  DynamicLibrary openNotcurses() {
    if (Platform.isMacOS) {
      return DynamicLibrary.open(_resolveMac('libnotcurses.dylib'));
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libnotcurses.so');
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  DynamicLibrary openNotcursesInline() {
    if (Platform.isMacOS) {
      return DynamicLibrary.open(_resolveMac('libnotcurses-ffi.dylib'));
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libnotcurses-ffi.so');
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  String _resolveMac(String libName) {
    for (final p in _macPaths) {
      final file = File('$p/$libName');
      if (file.existsSync()) return file.path;
    }
    throw UnsupportedError(
      'Could not find $libName in ${_macPaths.join(" or ")}',
    );
  }
}
