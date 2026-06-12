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

This plan is divided into **five phases**. Each step includes a verification command. We'll add a `dart test` suite alongside the new code so future changes have a safety net.

---

## Phase 1: Environment Setup

### Step 1: Install notcurses 3.0.17

```bash
brew install notcurses
```

This installs v3.0.17 to `/usr/local/opt/notcurses/`, where the ffigen configs already point.

**Verify:**
```bash
# Confirm version 3.0.17 is installed
brew info notcurses | head -5

# Confirm headers are where ffigen expects them
ls /usr/local/opt/notcurses/include/notcurses/notcurses.h

# Confirm the library is loadable
ls /usr/local/opt/notcurses/lib/libnotcurses.dylib
```

---

## Phase 2: FFI Layer

### Step 2: Add new inline function declarations to `ffi/ffi.c`

Add the two new inline functions to the C shim file that ffigen reads for inline bindings:

```c
bool notcurses_canoctant(const struct notcurses* nc);
bool ncdirect_canoctant(const struct ncdirect* nc);
```

These need to be added alongside the other `notcurses_can*` and `ncdirect_can*` declarations.

**Verify:**
```bash
grep -n 'canoctant' ffi/ffi.c
# Should show both declarations
```

### Step 3: Regenerate FFI bindings

Run both ffigen passes against the updated headers:

```bash
# Main library bindings (picks up ncplane_family_destroy, NCBLIT_4x2, nccapabilities.octants)
dart run ffigen --config ./ffi/notcurses.yml

# Inline function bindings (picks up canoctant functions)
./ffi/gen_inline.sh
```

**Verify — check that each new symbol appears in the generated bindings:**
```bash
# NCBLIT_4x2 in the blitter enum
grep -n 'NCBLIT_4x2' lib/src/ffi/notcurses_g.dart

# octants field in the capabilities struct
grep -n 'octants' lib/src/ffi/notcurses_g.dart

# ncplane_family_destroy function
grep -n 'ncplane_family_destroy' lib/src/ffi/notcurses_g.dart

# canoctant inline functions
grep -n 'canoctant' lib/src/ffi/notcurses_inline_g.dart
```

**Verify — static analysis still passes (0 issues):**
```bash
dart analyze
# Expected: "No issues found."
```

> **Note:** `dart analyze` is critical here — the generated bindings must type-check under strict mode (`implicit-casts: false`, `implicit-dynamic: false`, `strict-raw-types: true`). If ffigen produces ill-typed output, this step will catch it before we build wrappers on top.

### Step 4: Archive the current C shim

Copy `ffi/ffi.c` → `ffi/ffi_307.c` as a versioned snapshot (if not already matching the existing `ffi_307.c`). The existing `ffi_307.c` uses self-contained typedefs (no `#include`), while `ffi.c` uses `#include <notcurses/notcurses.h>`. Verify they're aligned and save the current state.

**Verify:**
```bash
diff ffi/ffi.c ffi/ffi_307.c
# Should show only the new canoctant additions in ffi.c vs ffi_307.c
```

---

## Phase 3: Dart Wrapper Layer

### Step 5: Update the Blitter constants (`lib/src/ptypes.dart`)

Add the new octant blitter constant to the `Blitter` abstract class:

```dart
/// octants (Unicode 16) - 4 rows, 2 cols
static const int blit_4x2 = ncblitter_e.NCBLIT_4x2;
```

**Verify:**
```bash
dart analyze lib/src/ptypes.dart
# Expected: "No issues found."

grep -n 'blit_4x2' lib/src/ptypes.dart
```

### Step 6: Update the Capabilities class (`lib/src/notcurses.dart`)

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

**Verify:**
```bash
dart analyze lib/src/notcurses.dart
# Expected: "No issues found."

grep -n 'octants' lib/src/notcurses.dart
```

### Step 7: Add `canOctant()` methods

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

**Verify:**
```bash
dart analyze lib/src/notcurses.dart lib/src/direct.dart
# Expected: "No issues found."

grep -n 'canOctant' lib/src/notcurses.dart lib/src/direct.dart
```

### Step 8: Add `Plane.familyDestroy()` (`lib/src/plane.dart`)

Add a method to destroy a plane and all its bound descendants:

```dart
/// Destroy this plane and all its bound descendants.
void familyDestroy() {
  nc.ncplane_family_destroy(ptr);
}
```

**Verify:**
```bash
dart analyze lib/src/plane.dart
# Expected: "No issues found."

grep -n 'familyDestroy' lib/src/plane.dart
```

---

## Phase 4: Test Suite

### Step 9: Add `test` dependency and test directory

Add to `pubspec.yaml` dev dependencies:

```yaml
dev_dependencies:
  lints: ^1.0.0
  ffigen: ^4.1.2
  test: ^1.24.0
```

Create `test/` directory.

**Verify:**
```bash
dart pub get
# Should resolve without errors
```

### Step 10: Write unit tests for pure Dart constructs (`test/wrapper_test.dart`)

These test the wrapper layer without needing a live notcurses instance:

```dart
import 'package:test/test.dart';
import 'package:dart_notcurses/dart_notcurses.dart';

void main() {
  group('Capabilities', () {
    test('defaults octants to false', () {
      const caps = Capabilities();
      expect(caps.octants, isFalse);
    });

    test('accepts octants: true', () {
      const caps = Capabilities(octants: true);
      expect(caps.octants, isTrue);
    });

    test('toString includes octants', () {
      const caps = Capabilities(octants: true);
      expect(caps.toString(), contains('octants'));
    });
  });

  group('Blitter', () {
    test('blit_4x2 is a valid int', () {
      expect(Blitter.blit_4x2, isA<int>());
      expect(Blitter.blit_4x2, greaterThanOrEqualTo(0));
    });
  });
}
```

**Verify:**
```bash
dart test test/wrapper_test.dart
# All tests pass
```

### Step 11: Write FFI integration tests (`test/ffi_test.dart`)

These test that the new symbols exist and are callable with notcurses installed. They use `Direct` mode (no full rendering context needed) and redirect output to avoid terminal requirements:

```dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_notcurses/dart_notcurses.dart';

void main() {
  group('FFI symbols', () {
    test('ncplane_family_destroy is bound', () {
      // Verify the symbol resolves at all (will throw if missing)
      expect(() => nc.ncplane_family_destroy, returnsNormally);
    });
  });

  group('Direct mode', () {
    late Direct nc;

    setUp(() {
      // Redirect stdout so ncdirect doesn't need a real terminal
      nc = Direct();
    });

    tearDown(() {
      nc.stop();
    });

    test('canOctant returns bool', () {
      expect(nc.canOctant(), isA<bool>());
    });

    test('capabilities includes octants', () {
      final caps = nc.capabilities();
      expect(caps.octants, isA<bool>());
    });
  });
}
```

> **Note:** Integration tests require notcurses to be installed. They may fail in headless CI unless `TERM` is set (e.g. `TERM=xterm-256color`). If that's a concern, guard them with a skip condition:
> ```dart
> final hasNotcurses = File('/usr/local/opt/notcurses/lib/libnotcurses.dylib').existsSync();
> group('Direct mode', skip: !hasNotcurses, () { ... });
> ```

**Verify:**
```bash
dart test test/ffi_test.dart
# All tests pass (requires notcurses installed)
```

### Step 12: Run full test suite

```bash
dart test
# Runs all tests in test/
```

---

## Phase 5: Final Verification

### Step 13: Full static analysis

```bash
dart analyze
# Expected: "No issues found." — 0 errors, 0 warnings, 0 infos
```

### Step 14: Run examples as smoke tests

These exercise version detection, capabilities, and rendering end-to-end:

```bash
# Tests init, capabilities (including octants), version info, and clean shutdown
dart run examples/nc-info.dart

# Tests direct-mode capabilities including canOctant
dart run examples/direct_test.dart

# Tests full-mode rendering with blitters (including the new NCBLIT_4x2)
dart run examples/blitters.dart
```

> **Note:** These examples require a terminal. Run them in an interactive session to confirm they render correctly. If running headless (e.g. CI), skip these and rely on `dart analyze` + `dart test`.

### Step 15: Diff review

Confirm only the expected files changed:

```bash
git diff --stat
```

Expected changed files:
| File | Change |
|---|---|
| `ffi/ffi.c` | Add `notcurses_canoctant` + `ncdirect_canoctant` declarations |
| `lib/src/ffi/notcurses_g.dart` | **Auto-regenerated** — picks up `NCBLIT_4x2`, `octants` field, `ncplane_family_destroy` |
| `lib/src/ffi/notcurses_inline_g.dart` | **Auto-regenerated** — picks up `canoctant` functions |
| `lib/src/ptypes.dart` | Add `blit_4x2` to `Blitter` class |
| `lib/src/notcurses.dart` | Add `octants` to `Capabilities`, add `canOctant()` |
| `lib/src/direct.dart` | Add `canOctant()` |
| `lib/src/plane.dart` | Add `familyDestroy()` |
| `test/wrapper_test.dart` | **New** — unit tests for Capabilities, Blitter |
| `test/ffi_test.dart` | **New** — integration tests for new FFI symbols |

---

## Out of scope

- **SDK constraint** (`>=2.15.1 <3.0.0`) — modernizing to Dart 3 is a separate concern
- **Platform support** (currently macOS-only) — adding Linux support is orthogonal
- **Deprecated API cleanup** (`ncinput.alt`, `.shift`, `.ctrl` booleans) — informational only, no action needed until 4.0
