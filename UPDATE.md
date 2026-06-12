# Plan: Update dart_notcurses to support notcurses 3.0.17

## Context

The dart_notcurses project currently targets **notcurses ~3.0.7** (the latest C shim is `ffi_307.c`). The latest notcurses release is **v3.0.17**. The 3.0.x series has been additive — no APIs were removed or had breaking signature changes. The main additions since 3.0.7 are:

| Addition | Version | Type |
|---|---|---|
| `NCBLIT_4x2` (octant blitter) | 3.0.12 | enum value |
| `notcurses_canoctant()` | 3.0.12 | inline function |
| `ncdirect_canoctant()` | 3.0.12 | inline function |
| `nccapabilities.octants` field | 3.0.12 | struct field |

And one non-inline function:
| `ncplane_family_destroy()` | 3.0.14 | library function |

## Approach

Since notcurses is **not currently installed** (`brew info notcurses` shows "Not installed"), we need to install it before we can regenerate the ffigen bindings. The update has two layers:

1. **FFI layer** — regenerate auto-generated bindings from updated C headers
2. **Dart wrapper layer** — expose new APIs through the idiomatic Dart classes

---

## Step 1: Install notcurses 3.0.17

```bash
brew install notcurses
```

This installs v3.0.17 to `/usr/local/opt/notcurses/`, where the ffigen configs already point.

## Step 2: Add new inline function declarations to `ffi/ffi.c`

Add the two new inline functions to the C shim file that ffigen reads for inline bindings:

```c
bool notcurses_canoctant(const struct notcurses* nc);
bool ncdirect_canoctant(const struct ncdirect* nc);
```

These need to be added alongside the other `notcurses_can*` and `ncdirect_can*` declarations.

## Step 3: Regenerate FFI bindings

Run both ffigen passes against the updated headers:

```bash
# Main library bindings (picks up ncplane_family_destroy, NCBLIT_4x2, nccapabilities.octants)
dart run ffigen --config ./ffi/notcurses.yml

# Inline function bindings (picks up canoctant functions)
./ffi/gen_inline.sh
```

After regeneration, the following will appear automatically:
- `NCBLIT_4x2` in the `ncblitter_e` enum
- `octants` field in the `nccapabilities` struct
- `ncplane_family_destroy` in the `NcFfi` class
- `notcurses_canoctant` / `ncdirect_canoctant` in the `NcFfiInline` class

## Step 4: Archive the current C shim

Copy `ffi/ffi.c` → `ffi/ffi_307.c` as a versioned snapshot (if not already matching the existing `ffi_307.c`). The existing `ffi_307.c` uses self-contained typedefs (no `#include`), while `ffi.c` uses `#include <notcurses/notcurses.h>`. Verify they're aligned and save the current state.

## Step 5: Update the Dart Blitter constants (`lib/src/ptypes.dart`)

Add the new octant blitter constant to the `Blitter` abstract class:

```dart
/// octants (Unicode 16) - 4 rows, 2 cols
static const int blit_4x2 = ncblitter_e.NCBLIT_4x2;
```

## Step 6: Update the Capabilities class (`lib/src/notcurses.dart`)

Add the `octants` field:

```dart
class Capabilities {
  // ... existing fields ...
  final bool octants;

  const Capabilities({
    // ... existing params ...
    this.octants = false,
  });
}
```

Update the `capabilities()` method to read the new field:

```dart
octants: cpr.octants > 0,
```

Update the `toString()` to include `octants`.

## Step 7: Add `canOctant()` methods

**`NotCurses` class** (`lib/src/notcurses.dart`):
```dart
/// Can we reliably use Unicode 16 octants?
bool canOctant() {
  return ncInline.notcurses_canoctant(_ptr) != 0;
}
```

**`Direct` class** (`lib/src/direct.dart`):
```dart
/// Can we reliably use Unicode 16 octants?
bool canOctant() {
  return ncInline.ncdirect_canoctant(_ptr) != 0;
}
```

## Step 8: Add `Plane.familyDestroy()` (`lib/src/plane.dart`)

Add a method to destroy a plane and all its bound descendants:

```dart
/// Destroy this plane and all its bound descendants.
void familyDestroy() {
  nc.ncplane_family_destroy(ptr);
}
```

## Step 9: Verify

Run the examples to confirm everything works:

```bash
dart run examples/nc-info.dart
```

This exercises version detection, capabilities, and rendering — a good smoke test for the updated bindings.

---

## Files to modify

| File | Change |
|---|---|
| `ffi/ffi.c` | Add `notcurses_canoctant` + `ncdirect_canoctant` declarations |
| `lib/src/ffi/notcurses_g.dart` | **Auto-regenerated** — picks up `NCBLIT_4x2`, `octants` field, `ncplane_family_destroy` |
| `lib/src/ffi/notcurses_inline_g.dart` | **Auto-regenerated** — picks up `canoctant` functions |
| `lib/src/ptypes.dart` | Add `blit_4x2` to `Blitter` class |
| `lib/src/notcurses.dart` | Add `octants` to `Capabilities`, add `canOctant()` |
| `lib/src/direct.dart` | Add `canOctant()` |
| `lib/src/plane.dart` | Add `familyDestroy()` |

## Out of scope

- **SDK constraint** (`>=2.15.1 <3.0.0`) — modernizing to Dart 3 is a separate concern
- **Platform support** (currently macOS-only) — adding Linux support is orthogonal
- **Test suite** — there are no existing tests; adding them is a separate task
- **Deprecated API cleanup** (`ncinput.alt`, `.shift`, `.ctrl` booleans) — informational only, no action needed until 4.0
