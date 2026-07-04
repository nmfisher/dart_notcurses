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
    // separate libtinfo (terminfo lives in libncurses). On macOS notcurses-core's
    // transitive deps are statically embedded from vendored archives, so the
    // merged dylib has no runtime Homebrew dependency; on Linux they stay system
    // shared libraries (-l flags).
    final isMacOS = targetOS == OS.macOS;

    // Vendored transitive deps linked statically on macOS (next to
    // libnotcurses-core.a in native/lib/<os>_<arch>/). Linux keeps using system
    // shared libs.
    const macosDeps = ['libncursesw.a', 'libunistring.a', 'libdeflate.a'];

    // Verify every required archive is present before linking, so a missing
    // vendored dep surfaces a clear pointer to the build script instead of an
    // opaque "file not found" from ld.
    for (final name in [
      'libnotcurses-core.a',
      if (isMacOS) ...macosDeps,
    ]) {
      final archive = p.join(libDir, name);
      if (!File(archive).existsSync()) {
        throw UnsupportedError(
          'Missing vendored static archive for $targetOS/$targetArch: $name\n'
          'Looked in: $archive\n'
          '(Re)build the vendored archives with tool/build_notcurses.sh.',
        );
      }
    }

    // -force_load (macOS) / --whole-archive (Linux) is LOAD-BEARING. The Dart
    // @Native externals reference notcurses symbols that no C glue (ffi.c /
    // shim.c) actually calls, so the linker sees no C-side reference to most of
    // the notcurses-core API. Without forcing the whole archive in, those
    // objects would be dropped and the bindings would resolve to undefined
    // symbols at runtime. Forcing it all in re-exports the full API.
    final notcursesArchive = '$libDir/libnotcurses-core.a';

    final flags = <String>[
      '-DNOTCURSES_FFI',
      '-D_GNU_SOURCE',
      '-D_DEFAULT_SOURCE',
      '-L$libDir',
      if (isMacOS) ...[
        '-force_load',
        notcursesArchive,
        for (final dep in macosDeps) '$libDir/$dep',
      ] else ...[
        '-Wl,--whole-archive',
        notcursesArchive,
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
