# Plan: Migrate ffigen 4.x → 20.x

## Context

The project uses ffigen 4.1.2 to generate FFI bindings. We're upgrading to ffigen 20.1.1 (latest) to stay current. The main challenge is that ffigen 20.x generates Dart 3 code with different type mappings and struct handling. We've tested the key config options and confirmed a working approach.

## Key Config Changes

### Both configs
- Remove `dart-bool: false` (no longer a valid key; not needed with `type-map` for bool)
- Add `silence-enum-warning: true`
- Add `enums.as-int: { include: ['.*'] }` to keep enums as int constants (compatible with current wrapper)
- Minimum SDK → `>=3.0.0` (required for `sealed class`, `final class`)

### `ffi/notcurses.yml`
- Update `output` path from `'lib/src/ffi/notcurses_g.dart'` to `'../lib/src/ffi/notcurses_g.dart'` (ffigen 20.x resolves relative to config file)
- Update header paths to `/usr/local/include/...` for Linux (keep macOS comment)
- Remove `dart-bool: false`

### `ffi/inline.yml`
- Update `output` path to `'../lib/src/ffi/notcurses_inline_g.dart'`
- Update entry-points from `'./ffi/ffi.c'` to `'./ffi.c'` (relative to config dir)
- Update compiler-opts path
- Replace `typedef-map: 'bool': 'Int8'` with `type-map: native-types: bool: ...` (new format)
- Add `library-imports` + `type-map: structs:` to reference types from notcurses_g.dart (eliminates duplicate structs — the key discovery)
- Add `ignore-source-errors: true` (ffi.c has wchar_t/ncalign_e errors)
- Remove preamble import (type-map handles it)

### `ffi/gen_inline.sh`
- Strip stray typedefs at end of file (`typedef bool = ...`, `typedef Dartbool = ...`)
- Keep existing sed for renaming numbered duplicates as fallback

## Wrapper Layer Changes

### `UnsignedInt` → update `alloc` calls (~30 sites)
ffigen 20.x uses `ffi.UnsignedInt` for C `unsigned int` and `ffi.Uint32` for `uint32_t`. Struct pointer params change accordingly. Update all `alloc<ffi.Uint32>()` that correspond to `unsigned *` params to `alloc<ffi.UnsignedInt>()`.

Files with `alloc<ffi.Uint32()>`:
- `lib/src/channels.dart` — 9 calls
- `lib/src/cell.dart` — 6 calls
- `lib/src/plane.dart` — 8 calls
- `lib/src/notcurses.dart` — 2 calls
- `lib/src/pixelgeom_data.dart` — 6 calls
- `lib/src/visual.dart` — 1 call
- `lib/src/direct.dart` — 2 calls

Strategy: after regenerating, grep for `UnsignedInt` in the generated bindings to identify which struct fields use it, then update matching `alloc<>` calls. Many of these allocate `unsigned *` out-params for functions like `ncplane_dim_yx` — these must change to `alloc<ffi.UnsignedInt>()`.

### No changes needed
- `lib/src/ptypes.dart` — enum references stay as `static const int` (via `as-int`)
- `lib/src/key.dart` — struct field access still returns `int`
- `lib/src/menu.dart` — no inline calls

## Implementation Steps

### Step 1: Update pubspec.yaml
- `ffigen: ^20.1.0`
- `sdk: '>=3.0.0 <4.0.0'`
- `dart pub get`

### Step 2: Update `ffi/notcurses.yml`
- Paths, enum config, remove `dart-bool`

### Step 3: Regenerate `lib/src/ffi/notcurses_g.dart`
- `dart run ffigen --config ./ffi/notcurses.yml`

### Step 4: Update `ffi/inline.yml`
- Paths, library-imports, type-map for struct sharing, ignore-source-errors

### Step 5: Update `ffi/gen_inline.sh`
- Strip stray typedefs (`typedef bool =`, `typedef Dartbool =`)

### Step 6: Regenerate `lib/src/ffi/notcurses_inline_g.dart`
- `./ffi/gen_inline.sh`

### Step 7: Fix `alloc<ffi.Uint32()>` → `alloc<ffi.UnsignedInt>()` in wrapper files
- Grep for `UnsignedInt` in generated bindings to identify which fields changed
- Update matching alloc calls

### Step 8: `dart analyze` + `dart test`

### Step 9: Commit

## Verification

```bash
dart analyze          # 0 issues
dart test             # 11/11 pass
grep -c 'canoctant\|NCBLIT_4x2\|octants\|family_destroy' lib/src/ffi/notcurses_g.dart lib/src/ffi/notcurses_inline_g.dart
```
