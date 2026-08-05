#!/usr/bin/env bash
#
# Build the vendored static notcurses artifacts for native Windows (x64) and
# stage them into native/lib/windows_x64/, where hook/build.dart links them
# into the package's notcurses_merged.dll.
#
# WHAT THIS PRODUCES in native/lib/windows_x64/:
#   libnotcurses-core.a   -- built here from the notcurses source
#   libncursesw.a         -- copied from the MSYS2 UCRT64 prefix (terminfo is
#                            folded into this archive; there is no libtinfow.a)
#   libunistring.a        -- copied from the MSYS2 UCRT64 prefix
#   libdeflate.a          -- copied from the MSYS2 UCRT64 prefix
#   libwinpthread.a       -- copied from the MSYS2 UCRT64 prefix (mingw pthreads)
#   LICENSES/             -- license texts for the above
#
# All transitive deps are vendored as static archives and -whole-archive'd /
# -static'd into notcurses_merged.dll at link time (see hook/build.dart), so the
# resulting DLL has NO runtime dependency on mingw/MSYS2 DLLs (libgcc, winpthread,
# libtinfow-6.dll, etc.). End users therefore do not need MSYS2 installed to run
# cocoon -- only to *build* it from source.
#
# IMPORTANT: this script must be run from an MSYS2 UCRT64 shell (the "UCRT64"
# mingw environment). notcurses does not build with MSVC; mingw-w64 is the only
# supported Windows toolchain. Verify with `pacman -Q mingw-w64-ucrt-x86_64-gcc`.
#
# Usage:
#   ./tool/build_notcurses_windows_x64.sh            # build for windows_x64
#   NOTCURSES_VERSION=3.0.17 ./tool/build_notcurses_windows_x64.sh
#
# Requirements (in an MSYS2 UCRT64 shell):
#   pacman -S --needed git mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,pkg-config,ncurses,libunistring,libdeflate,winpthreads}
#
set -euo pipefail

NOTCURSES_VERSION="${NOTCURSES_VERSION:-3.0.17}"
NOTCURSES_REPO="https://github.com/dankamongmen/notcurses.git"

# Resolve paths relative to this script so it runs from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PKG_ROOT/native/.build/notcurses"
OUT_BASE="$PKG_ROOT/native/lib"

# ---- host platform / arch -> dart_notcurses target dir ---------------------
# We only support native Windows here, and only x64 for now. The script is meant
# to run inside MSYS2 UCRT64, where `uname -s` is e.g. MINGW64_NT-10.0-19045.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) HOST_OS="windows" ;;
  *) echo "error: this script builds for native Windows; run it inside an MSYS2 UCRT64 shell." >&2
     echo "       (uname -s = $(uname -s))" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) HOST_ARCH="x64" ;;
  *) echo "error: unsupported arch for this script: $(uname -m) (only x64 today)" >&2; exit 1 ;;
esac
OUT_DIR="$OUT_BASE/${HOST_OS}_${HOST_ARCH}"
echo "==> target: ${HOST_OS}_${HOST_ARCH}  ->  $OUT_DIR"

# ---- toolchain checks -------------------------------------------------------
# In an MSYS2 UCRT64 shell the mingw toolchain lives under /ucrt64 (MSYS2 mounts
# the UCRT64 root at /ucrt64). Bail early if it isn't present so failures are
# obvious.
UCRT_PREFIX="${UCRT64_PREFIX:-/ucrt64}"
if [ ! -d "$UCRT_PREFIX/bin" ]; then
  echo "error: MSYS2 UCRT64 prefix not found at $UCRT_PREFIX/bin" >&2
  echo "       Install MSYS2, open the 'UCRT64' shell, then:" >&2
  echo "         pacman -S --needed mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,pkg-config,ncurses,libunistring,libdeflate,winpthreads}" >&2
  exit 1
fi
export PATH="$UCRT_PREFIX/bin:$PATH"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found in PATH ($UCRT_PREFIX/bin)" >&2; exit 1; }; }
need git
need cmake
need pkg-config
# Force the UCRT64 gcc/g++ explicitly; native_toolchain_c's CBuilder (and CMake)
# both honor CC/CXX, and on Windows we must avoid MSVC.
export CC="${CC:-$UCRT_PREFIX/bin/gcc.exe}"
export CXX="${CXX:-$UCRT_PREFIX/bin/g++.exe}"
if command -v ninja >/dev/null 2>&1; then GEN="Ninja"; else GEN="MSYS Makefiles"; fi

# ---- fetch / update notcurses source ----------------------------------------
# v3.0.17 is an ANNOTATED tag. A naive `git clone --depth 1 --branch <tag>`
# fetches the tag object but, on a shallow clone, not always the commit it
# points at -- git then falls back to the default branch HEAD and the patches
# below fail to apply. Fetch the tag explicitly with `git fetch ... tag`, which
# pulls the tag and the commit it dereferences, then verify we actually landed
# on v$NOTCURSES_VERSION before patching.
if [ -d "$SRC_DIR/.git" ]; then
  echo "==> using existing source at $SRC_DIR"
  git -C "$SRC_DIR" remote remove origin 2>/dev/null || true
  git -C "$SRC_DIR" remote add origin "$NOTCURSES_REPO"
  git -C "$SRC_DIR" fetch --depth 1 origin "tag" "v$NOTCURSES_VERSION"
else
  echo "==> cloning notcurses v$NOTCURSES_VERSION"
  mkdir -p "$(dirname "$SRC_DIR")"
  git init "$SRC_DIR"
  git -C "$SRC_DIR" remote add origin "$NOTCURSES_REPO"
  git -C "$SRC_DIR" fetch --depth 1 origin "tag" "v$NOTCURSES_VERSION"
fi
git -C "$SRC_DIR" checkout -q "v$NOTCURSES_VERSION"

# Fail fast if the checkout didn't land on the tagged commit (avoids opaque
# patch-apply failures downstream).
tagged_commit="$(git -C "$SRC_DIR" rev-parse "v${NOTCURSES_VERSION}^{commit}")"
head_commit="$(git -C "$SRC_DIR" rev-parse HEAD)"
if [ "$tagged_commit" != "$head_commit" ]; then
  echo "error: checkout of v$NOTCURSES_VERSION did not land on the tag's commit." >&2
  echo "       tag dereferences to $tagged_commit, HEAD is $head_commit" >&2
  exit 1
fi

# Apply Cocoon's small input extension after checking out the pristine tag.
# The patch files are LF in the repo (see .gitattributes), but defensively
# strip any stray CR before applying: `git apply` matches context byte-for-byte
# and a CRLF patch silently fails against the LF notcurses source.
apply_patch() {  # <patch path>
  sed 's/\r$//' "$1" | git -C "$SRC_DIR" apply --check -p1 - && \
  sed 's/\r$//' "$1" | git -C "$SRC_DIR" apply -p1 -
}
PASTE_PATCH="$PKG_ROOT/native/patches/notcurses-paste-events.patch"
if ! git -C "$SRC_DIR" diff --quiet -- include/notcurses/nckeys.h src/lib/in.c; then
  git -C "$SRC_DIR" checkout -- include/notcurses/nckeys.h src/lib/in.c
fi
apply_patch "$PASTE_PATCH"

# Flip the static targets from -fPIE to -fPIC (see build_notcurses.sh for the
# rationale). On Windows/PE this is harmless but keeps the patch applying
# uniformly across platforms.
PIC_PATCH="$PKG_ROOT/native/patches/notcurses-static-pic.patch"
git -C "$SRC_DIR" checkout -- CMakeLists.txt
apply_patch "$PIC_PATCH"

BUILD_DIR="$SRC_DIR/build"
mkdir -p "$BUILD_DIR"

# ---- CMake configure --------------------------------------------------------
# Core-only: no FFmpeg multimedia, no C++/pandoc/pocs/executables/ffi lib.
# Point CMake at the UCRT64 prefix so terminfo/ncursesw/deflate resolve to the
# mingw (not MSVC) builds.
#
# NCURSES_STATIC is load-bearing: MSYS2's ncurses headers decorate the terminfo
# entry points (tigetstr/tigetflag/tigetnum/...) with __declspec(dllimport)
# unless NCURSES_STATIC is defined (ncurses_dll.h). Without it, notcurses-core's
# objects reference __imp_tigetstr etc., which the STATIC libncursesw.a we vendor
# does NOT provide -> "undefined reference to __imp_tigetstr" at final link.
# Defining NCURSES_STATIC makes those references plain (tigetstr), which the
# static archive defines.
export CFLAGS="${CFLAGS:-} -DNCURSES_STATIC"
export CXXFLAGS="${CXXFLAGS:-} -DNCURSES_STATIC"
CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DUSE_MULTIMEDIA=none
  -DUSE_PANDOC=OFF
  -DUSE_CXX=OFF
  -DBUILD_EXECUTABLES=OFF
  -DUSE_POC=OFF
  -DBUILD_FFI_LIBRARY=OFF
  -DCMAKE_PREFIX_PATH="$UCRT_PREFIX"
  -DCMAKE_FIND_ROOT_PATH="$UCRT_PREFIX"
  -DCMAKE_INSTALL_PREFIX="$UCRT_PREFIX"
)

echo "==> cmake configure ($GEN, CC=$CC)"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G "$GEN" "${CMAKE_ARGS[@]}"

echo "==> cmake build notcurses-core-static"
cmake --build "$BUILD_DIR" -j --target notcurses-core-static

# ---- stage libnotcurses-core.a ---------------------------------------------
CORE_A="$BUILD_DIR/libnotcurses-core.a"
[ -f "$CORE_A" ] || { echo "error: build did not produce $CORE_A" >&2; exit 1; }
mkdir -p "$OUT_DIR"
cp "$CORE_A" "$OUT_DIR/libnotcurses-core.a"
echo "==> staged $OUT_DIR/libnotcurses-core.a"

# ---- stage vendored static deps (so the DLL has zero runtime deps) ---------
# Every dep is linked statically at final-link time (hook/build.dart). We grab
# them from the UCRT64 prefix. Both libncursesw.a and libtinfow.a are staged:
# on some ncurses builds terminfo is split out into libtinfo, on others it is
# folded into libncurses; staging both lets the linker use whichever resolves.
stage_dep() {  # <source path> <out name>
  if [ -f "$1" ]; then
    cp "$1" "$OUT_DIR/$2"
    echo "==> staged $OUT_DIR/$2"
  else
    echo "==> note: optional dep not present, skipping: $1" >&2
  fi
}

stage_dep "$UCRT_PREFIX/lib/libncursesw.a"  libncursesw.a
stage_dep "$UCRT_PREFIX/lib/libunistring.a" libunistring.a
stage_dep "$UCRT_PREFIX/lib/libdeflate.a"   libdeflate.a
stage_dep "$UCRT_PREFIX/lib/libwinpthread.a" libwinpthread.a

# ---- licenses ---------------------------------------------------------------
LIC="$OUT_DIR/LICENSES"
mkdir -p "$LIC"
# ncurses / libdeflate / libunistring notices are hand-curated canonical text on
# macOS; for Windows we copy what the MSYS2 packages ship where available.
for src in \
  "$UCRT_PREFIX/share/licenses/ncurses/COPYING" \
  "$UCRT_PREFIX/share/licenses/libdeflate/COPYING" \
  "$UCRT_PREFIX/share/licenses/winpthreads/COPYING"; do
  [ -f "$src" ] && cp "$src" "$LIC/$(basename "$src")" || true
done
# libunistring ships LGPL under share/doc on MSYS2.
if [ -f "$UCRT_PREFIX/share/licenses/libunistring/COPYING.LIB" ]; then
  cp "$UCRT_PREFIX/share/licenses/libunistring/COPYING.LIB" "$LIC/libunistring.COPYING.LIB"
fi
echo "==> refreshed licenses in $LIC"

echo
echo "Done. Staged artifacts for ${HOST_OS}_${HOST_ARCH}:"
ls -1 "$OUT_DIR"/*.a
echo
echo "Next: from the package root (still in the UCRT64 shell), run 'dart test'"
echo "(or dart run) to relink notcurses_merged.dll against these archives."
