import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageRoot = input.packageRoot;
    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    // Resolve platform-specific static lib directory
    final libDir = p.join(
      packageRoot.toFilePath(),
      'native',
      'lib',
      '${targetOS.name}_${targetArch.name}',
    );

    if (!Directory(libDir).existsSync()) {
      throw UnsupportedError(
        'No pre-built static libraries for $targetOS/$targetArch. '
        'Directory not found: $libDir',
      );
    }

    // The merged-library link step differs between GNU ld (Linux) and ld64
    // (macOS): macOS has no --whole-archive (use -force_load instead) and no
    // separate libtinfo (terminfo lives in libncurses). On macOS the core
    // deps are statically embedded so the merged dylib has no runtime
    // Homebrew dependency.
    final isMacOS = targetOS == OS.macOS;

    final flags = <String>[
      '-DNOTCURSES_FFI',
      '-D_GNU_SOURCE',
      '-D_DEFAULT_SOURCE',
      '-DXOPEN_SOURCE=700',
      '-L$libDir',
      if (isMacOS) ...[
        // -force_load pulls ALL objects from the archive into the merged lib
        // (the ld64 equivalent of --whole-archive) so the full notcurses-core
        // API is re-exported for the Dart FFI bindings.
        '-force_load',
        '$libDir/libnotcurses-core.a',
        // Statically embed notcurses-core's transitive deps. Homebrew ships
        // single-arch arm64 archives on Apple Silicon.
        '/opt/homebrew/opt/ncurses/lib/libncursesw.a',
        '/opt/homebrew/lib/libunistring.a',
        '/opt/homebrew/lib/libdeflate.a',
      ] else ...[
        // --whole-archive forces ALL symbols from the static archive to be
        // included, not just those referenced by ffi.c. This ensures the
        // merged library exports the full notcurses-core API.
        '-Wl,--whole-archive',
        '$libDir/libnotcurses-core.a',
        '-Wl,--no-whole-archive',
        '-ltinfo',
        '-lunistring',
        '-ldeflate',
        '-lm',
        '-lpthread',
      ],
    ];

    final cbuilder = CBuilder.library(
      name: 'notcurses_merged',
      assetName: 'dart_notcurses.dart',
      sources: [
        p.join('native', 'src', 'ffi.c'),
        p.join('native', 'src', 'shim.c'),
      ],
      includes: [
        p.join('native', 'include'),
      ],
      flags: flags,
      language: Language.c,
    );

    await cbuilder.run(input: input, output: output);
  });
}
