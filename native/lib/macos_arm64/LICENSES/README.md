# Vendored dependency archives (macOS arm64)

These static archives are linked into the package's merged dynamic library
(`notcurses_merged`) at build time by `hook/build.dart`, so the package links
entirely against checked-in statics and has **no Homebrew runtime dependency**.

| File | Library | License | Source |
| --- | --- | --- | --- |
| `libnotcurses-core.a` | notcurses core | Apache-2.0 | `../../include`, rebuilt via `tool/build_notcurses.sh` |
| `libncursesw.a` | ncurses | MIT-style ("ncurses license") | `./ncurses.LICENSE` |
| `libunistring.a` | GNU libunistring | **LGPL-3.0-or-later** | `./libunistring.COPYING`, `./libunistring.COPYING.LIB` |
| `libdeflate.a` | libdeflate | MIT | `./libdeflate.COPYING` |

## LGPL notice (libunistring)

`libunistring.a` is licensed under the GNU LGPL, which permits static linking
into a larger work provided the end user can re-link against a modified
version of the library. That requirement is satisfied here because:

1. The object archive (`libunistring.a`) is checked into this directory.
2. The build step that combines it with `libnotcurses-core.a`, `libncursesw.a`,
   and `libdeflate.a` into `notcurses_merged` is fully scripted
   (`hook/build.dart`), so a user can substitute a rebuilt `libunistring.a`
   and re-link by running `dart run`/`dart test`/`dart build` again.

To obtain the complete corresponding libunistring source for a given archive,
see https://www.gnu.org/software/libunistring/ (or `brew info libunistring`).

## Rebuilding

To rebuild any of these archives (e.g. after a notcurses/dependency version
bump, or for a new architecture), see `tool/build_notcurses.sh`.
