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
      final hint = targetOS == OS.windows
          ? '\nBuild them with tool/build_notcurses_windows_x64.sh '
              '(run inside an MSYS2 UCRT64 shell).'
          : '';
      throw UnsupportedError(
        'No pre-built static libraries for $targetOS/$targetArch. '
        'Directory not found: $libDir$hint',
      );
    }

    // The merged-library link step differs across GNU ld (Linux), ld64 (macOS),
    // and mingw-w64's ld (Windows): macOS has no --whole-archive (use -force_load
    // instead) and no separate libtinfo (terminfo lives in libncurses). On macOS
    // and Windows notcurses-core's transitive deps are statically embedded from
    // vendored archives, so the merged library has no runtime Homebrew/MSYS2
    // dependency; on Linux they stay system shared libraries (-l flags). On
    // Windows we additionally -static-libgcc so notcurses_merged.dll doesn't drag
    // in libgcc_s/libwinpthread runtime DLLs (end users need not have MSYS2
    // installed to *run* cocoon, only to build it from source).
    final isMacOS = targetOS == OS.macOS;
    final isWindows = targetOS == OS.windows;

    // Vendored transitive deps linked statically on macOS/Windows (next to
    // libnotcurses-core.a in native/lib/<os>_<arch>/). Linux keeps using system
    // shared libs.
    const macosDeps = ['libncursesw.a', 'libunistring.a', 'libdeflate.a'];
    // On MSYS2 mingw, terminfo is folded into libncursesw.a (there is no
    // separate libtinfow.a), so libncursesw.a supplies it. libwinpthread.a is
    // mingw's pthreads, needed by input_pump.c's stub today and the real
    // ConPTY pump later.
    const windowsDeps = [
      'libncursesw.a',
      'libunistring.a',
      'libdeflate.a',
      'libwinpthread.a',
    ];

    // Verify every required archive is present before linking, so a missing
    // vendored dep surfaces a clear pointer to the build script instead of an
    // opaque "file not found" from ld.
    final buildScript = isWindows
        ? 'tool/build_notcurses_windows_x64.sh (run inside an MSYS2 UCRT64 shell)'
        : 'tool/build_notcurses.sh';
    for (final name in [
      'libnotcurses-core.a',
      if (isMacOS) ...macosDeps,
      if (isWindows) ...windowsDeps,
    ]) {
      final archive = p.join(libDir, name);
      if (!File(archive).existsSync()) {
        throw UnsupportedError(
          'Missing vendored static archive for $targetOS/$targetArch: $name\n'
          'Looked in: $archive\n'
          '(Re)build the vendored archives with $buildScript.',
        );
      }
    }

    // -force_load (macOS) / --whole-archive (Linux + Windows) is LOAD-BEARING.
    // The Dart @Native externals reference notcurses symbols that no C glue
    // (ffi.c / shim.c) actually calls, so the linker sees no C-side reference to
    // most of the notcurses-core API. Without forcing the whole archive in, those
    // objects would be dropped and the bindings would resolve to undefined
    // symbols at runtime. Forcing it all in re-exports the full API.
    final notcursesArchive = '$libDir/libnotcurses-core.a';

    // Windows: native_toolchain_c's CBuilder is hardwired to MSVC for the
    // windows_x64 host/target combo (see CompilerResolver._selectPossibleCompilers
    // -- only `cl` is yielded, no mingw path, and CBuilder exposes no compiler
    // override). notcurses cannot be built/linked with MSVC, so on Windows we
    // bypass CBuilder and drive the MSYS2 UCRT64 mingw gcc directly. The hook
    // process inherits the UCRT64 shell's PATH, so `gcc` resolves directly.
    if (isWindows) {
      await _buildWindowsDllWithMingw(
        input: input,
        output: output,
        packageRoot: packageRoot,
        libDir: libDir,
        notcursesArchive: notcursesArchive,
        windowsDeps: windowsDeps,
      );
      return;
    }

    final flags = <String>[
      '-DNOTCURSES_FFI',
      '-D_GNU_SOURCE',
      '-D_DEFAULT_SOURCE',
      '-L$libDir',
      if (isMacOS) ...[
        '-Wl,-w', // suppress benign "built for newer macOS version" ld warnings
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
        p.join('native', 'src', 'input_pump.c'),
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

/// Builds notcurses_merged.dll on Windows by invoking the MSYS2 UCRT64 mingw
/// gcc directly (since native_toolchain_c only knows MSVC on Windows). Mirrors
/// what CBuilder.run would do: produce the shared library in the output dir and
/// register it as a bundled dynamic CodeAsset named 'dart_notcurses.dart'.
Future<void> _buildWindowsDllWithMingw({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Uri packageRoot,
  required String libDir,
  required String notcursesArchive,
  required List<String> windowsDeps,
}) async {
  final root = packageRoot.toFilePath();
  final outDir = input.outputDirectory;
  await Directory.fromUri(outDir).create(recursive: true);
  final dllUri = outDir.resolve(
    input.config.code.targetOS.libraryFileName(
      'notcurses_merged',
      DynamicLoadingBundled(),
    ),
  );

  // Find the mingw gcc: explicit override > PATH (e.g. MSYS2 UCRT64 shell) >
  // the default MSYS2 UCRT64 install location, so `dart run` works from any
  // shell (PowerShell, cmd) as long as MSYS2 UCRT64 is installed.
  final gcc = await _resolveMingwGcc();

  final include = p.join(root, 'native', 'include');
  final srcDir = p.join(root, 'native', 'src');
  final objDir = outDir.toFilePath();
  // -DNOTCURSES_FFI is scoped to ffi.c ONLY. It makes the notcurses headers
  // drop `static` from their inline functions so ffi.c re-exports them as the
  // single external definition for the @Native bindings. If shim.c /
  // input_pump.c are also compiled with it, they each emit those symbols as
  // strong globals too -> mingw ld "multiple definition" errors (Linux/macOS
  // tolerate the duplicate inline-definition copies; PE does not).
  final compileCommon = <String>[
    '-D_GNU_SOURCE',
    '-D_DEFAULT_SOURCE',
    // Match the notcurses-core build: use ncurses' terminfo entry points as
    // plain (static) symbols rather than __imp_ dllimport pointers.
    '-DNCURSES_STATIC',
    '-O2',
    '-DNDEBUG',
    '-I$include',
    '-c',
  ];
  final ffiObj = p.join(objDir, 'cocoon_ffi.o');
  final shimObj = p.join(objDir, 'cocoon_shim.o');
  final pumpObj = p.join(objDir, 'cocoon_input_pump.o');
  await _runGcc(gcc, [...compileCommon, '-DNOTCURSES_FFI',
    p.join(srcDir, 'ffi.c'), '-o', ffiObj]);
  await _runGcc(gcc, [...compileCommon,
    p.join(srcDir, 'shim.c'), '-o', shimObj]);
  await _runGcc(gcc, [...compileCommon,
    p.join(srcDir, 'input_pump.c'), '-o', pumpObj]);

  // mingw is in explicit-dllexport mode (notcurses marks its API dllexport), so
  // only dllexport symbols export; clock_gettime is pulled in (via -u below) but
  // lacks dllexport, so we force-export it with a .def file. mingw exports .def
  // symbols in ADDITION to dllexport ones, so the notcurses API stays exported.
  final defPath = p.join(objDir, 'cocoon_exports.def');
  await File(defPath).writeAsString(
    'LIBRARY notcurses_merged\nEXPORTS\n  clock_gettime\n',
  );

  final linkArgs = <String>[
    '-shared',
    '-o', dllUri.toFilePath(),
    defPath,
    ffiObj, shimObj, pumpObj,
    // clock_gettime (in libwinpthread.a) is looked up by the Dart bindings via
    // DynamicLibrary.process(); our stub input pump never references it, so the
    // linker would drop it. -u forces it undefined BEFORE the archives below are
    // scanned (archives are single-pass), so libwinpthread.a's object is pulled
    // in; the .def above then exports it.
    '-Wl,-u,clock_gettime',
    // Whole-archive notcurses-core (re-export the full API for @Native), then
    // its transitive deps statically, in dependency order.
    '-Wl,--whole-archive',
    notcursesArchive,
    '-Wl,--no-whole-archive',
    for (final dep in windowsDeps) '$libDir/$dep',
    // Windows system libs (import libs -> always-present system DLLs, so they
    // add no redistributable runtime dependency). secur32: GetUserNameExA
    // (notcurses util.c); advapi32/winmm: entry points pulled in by the static
    // ncurses/terminfo archive.
    '-lsecur32',
    '-ladvapi32',
    '-lwinmm',
    '-lws2_32', // WSAPoll (notcurses fd.c inputready on Windows)
    // Statically embed libgcc so the DLL has no libgcc_s_seh runtime dependency.
    // libwinpthread is already pulled in statically via libwinpthread.a above
    // (there's no -static-libwinpthread driver flag; linking the .a path is the
    // way). End users need not have MSYS2 to run.
    '-static-libgcc',
  ];
  await _runGcc(gcc, linkArgs);

  // Register the asset exactly like CBuilder.run does.
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'dart_notcurses.dart',
      file: dllUri,
      linkMode: DynamicLoadingBundled(),
    ),
    routing: ToAppBundle(),
  );

  output.dependencies.addAll({
    Uri.file(p.join(root, 'native', 'src', 'ffi.c')),
    Uri.file(p.join(root, 'native', 'src', 'shim.c')),
    Uri.file(p.join(root, 'native', 'src', 'input_pump.c')),
    Uri.directory(p.join(root, 'native', 'include')),
    Uri.file(notcursesArchive),
    for (final dep in windowsDeps) Uri.file('$libDir/$dep'),
  });
}

/// Resolves the MSYS2 UCRT64 mingw gcc to use for the Windows link.
///
/// Order: explicit `COCOON_MINGW_GCC` override > `gcc` on PATH (the case when
/// `dart run` is launched from an MSYS2 UCRT64 shell) > the default MSYS2 UCRT64
/// install path(s) (`C:\msys64\ucrt64\bin\gcc.exe`, ...). The last fallback lets
/// the build succeed from PowerShell/cmd without the UCRT64 shell on PATH.
Future<String> _resolveMingwGcc() async {
  final override = Platform.environment['COCOON_MINGW_GCC'];
  if (override != null && override.isNotEmpty) return override;

  try {
    final probe = await Process.run('gcc', ['--version']);
    if (probe.exitCode == 0) return 'gcc';
  } on ProcessException {
    // gcc not on PATH; fall through to filesystem lookup.
  }

  // MSYS2 default install roots.
  const roots = ['C:\\msys64', 'C:\\msys2'];
  for (final root in roots) {
    final candidate = '$root\\ucrt64\\bin\\gcc.exe';
    if (await File(candidate).exists()) return candidate;
  }

  // Let _runGcc surface a clear "not found" error.
  return 'gcc';
}

/// Runs [gcc] with [args], throwing a clear UnsupportedError (with stderr) on
/// non-zero exit, or if gcc could not be found/executed.
Future<void> _runGcc(String gcc, List<String> args) async {
  ProcessResult result;
  try {
    result = await Process.run(gcc, args);
  } on ProcessException catch (e) {
    final cmd = [gcc, ...args].join(' ');
    throw UnsupportedError(
      'Could not run mingw gcc ($gcc): $e\n'
      '  attempted command: $cmd\n'
      'Install MSYS2 UCRT64 (https://msys2.org) and the mingw-w64 toolchain, '
      'run from the MSYS2 UCRT64 shell, or set COCOON_MINGW_GCC to gcc.exe.',
    );
  }
  if (result.exitCode != 0) {
    final cmd = [gcc, ...args].join(' ');
    throw UnsupportedError(
      'mingw gcc failed (exit ${result.exitCode}):\n  $cmd\n'
      'stderr:\n${result.stderr}\nstdout:\n${result.stdout}',
    );
  }
}
