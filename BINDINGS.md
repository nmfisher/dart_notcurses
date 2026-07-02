# Native bindings pipeline

Everything native in this package is built from sources vendored in the repo —
never from a system notcurses install. One version of notcurses (see
`native/VERSION`) supplies the headers, the static library, and the generated
Dart bindings, so they cannot drift apart.

## Pieces

| Path | Role |
|---|---|
| `native/include/notcurses/*.h` | Vendored notcurses headers (single source of truth for the API) |
| `native/lib/<os>_<arch>/libnotcurses-core.a` | Vendored static notcurses, built per platform |
| `native/src/ffi.c` | Re-declares the header `static inline` functions without `static`; compiled with `-DNOTCURSES_FFI` this forces external symbol emission. **Also the ffigen entry point for the inline bindings** — one file defines both the exported symbols and the bindings. |
| `native/src/shim.c` | `notcurses_init`/`ncdirect_init` → `*_core_init` pass-throughs (core-only build) |
| `hook/build.dart` | Compiles the two shim files, links `libnotcurses-core.a` whole-archive plus deps into one merged dylib/so, and declares it as the code asset `package:dart_notcurses/dart_notcurses.dart` |
| `ffi/notcurses.yml` | ffigen config for the main bindings (`lib/src/ffi/notcurses_g.dart`) from the vendored headers |
| `ffi/inline.yml` | ffigen config for the inline bindings (`lib/src/ffi/notcurses_inline_g.dart`) from `native/src/ffi.c` |

## How the bindings load

The generated files use `@Native` externals under
`@DefaultAsset('package:dart_notcurses/dart_notcurses.dart')`. The Dart SDK
resolves that asset to the library built by the hook — for `dart run`,
`dart test`, and `dart build` alike. There is **no `DynamicLibrary.open` and
no path logic anywhere**; wrapper code simply imports the generated files:

```dart
import './ffi/notcurses_g.dart';                        // types (structs, enums, consts)
import './ffi/notcurses_g.dart' as nc;                  // functions: nc.ncplane_destroy(...)
import './ffi/notcurses_inline_g.dart' as ncInline;     // inline fns: ncInline.nccell_init(...)
```

## Regenerating

```bash
tool/regen_bindings.sh
```

Notes baked into the configs:

- `functions.exclude` drops the variadic `ncplane_printf*`/`ncplane_vprintf*`
  (not callable through dart:ffi).
- `inline.yml` passes `-DNOTCURSES_FFI` (drops `static`, matching how the shim
  TU is compiled) and `-Dinline=` (parse-only: ffigen refuses to bind
  functions whose inline bodies it can see, but the shim exports real symbols
  for every declaration in `native/src/ffi.c`).
- Header `_Bool` binds as `ffi.Bool`, `wchar_t` as `ffi.WChar` — real types,
  no type-map hacks, no post-processing of the generated output.

## Adding an inline function

1. Add its declaration to `native/src/ffi.c` (copy the prototype from the
   header, drop `static inline`). A wrong signature is a compile error.
2. `tool/regen_bindings.sh`
3. Expose it in the wrapper layer; `dart test`.

## Updating notcurses

1. Rebuild `native/lib/<os>_<arch>/libnotcurses-core.a` from the new release
   and refresh `native/include/notcurses/*.h` + `native/VERSION` from the same
   tree (see the build notes in the repo memory / commit history for CMake
   flags).
2. `tool/regen_bindings.sh` — the bindings pick up new structs/functions from
   the vendored headers only.
3. Add declarations for any new inline functions you need (step above).
4. `dart analyze && dart test` — the ptypes pin tests in
   `test/shared_utils_test.dart` catch silent constant/enum drift.
