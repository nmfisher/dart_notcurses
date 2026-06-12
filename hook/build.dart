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
      flags: [
        '-DNOTCURSES_FFI',
        '-D_GNU_SOURCE',
        '-D_DEFAULT_SOURCE',
        '-DXOPEN_SOURCE=700',
        '-L$libDir',
        // --whole-archive forces ALL symbols from the static archives to be
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
      language: Language.c,
    );

    await cbuilder.run(input: input, output: output);
  });
}
