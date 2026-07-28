#!/usr/bin/env bash
#
# Build the vendored static notcurses artifacts for the *host* platform/arch
# and stage them into native/lib/<os>_<arch>/, where hook/build.dart links them
# into the package's merged dynamic library.
#
# What this produces in native/lib/<os>_<arch>/:
#   libnotcurses-core.a   -- built here from the notcurses source
#   libncursesw.a         -- copied from Homebrew (macOS only)
#   libunistring.a        -- copied from Homebrew (macOS only)
#   libdeflate.a          -- copied from Homebrew (macOS only)
#   LICENSES/             -- license texts for the above
#
# On Linux the transitive deps stay system shared libraries (-l flags in
# build.dart), so only libnotcurses-core.a is staged there.
#
# Usage:
#   ./tool/build_notcurses.sh            # build for host arch (default)
#   NOTCURSES_VERSION=3.0.17 ./tool/build_notcurses.sh
#
# Requirements:
#   git, cmake, pkg-config, a C compiler, and (preferred) ninja.
#   macOS: `brew install ncurses libunistring libdeflate ninja cmake pkg-config`
#   Linux: the notcurses build deps via your package manager.
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
case "$(uname -s)" in
  Darwin) HOST_OS="macos" ;;
  Linux)  HOST_OS="linux" ;;
  *) echo "error: unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) HOST_ARCH="arm64" ;;
  x86_64|amd64)  HOST_ARCH="x64" ;;
  *) echo "error: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
OUT_DIR="$OUT_BASE/${HOST_OS}_${HOST_ARCH}"
echo "==> target: ${HOST_OS}_${HOST_ARCH}  ->  $OUT_DIR"

# ---- toolchain checks -------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found in PATH" >&2; exit 1; }; }
need git
need cmake
need pkg-config
if command -v ninja >/dev/null 2>&1; then GEN="Ninja"; else GEN="Unix Makefiles"; fi

# ---- fetch / update notcurses source ----------------------------------------
if [ -d "$SRC_DIR/.git" ]; then
  echo "==> using existing source at $SRC_DIR"
  git -C "$SRC_DIR" fetch --depth 1 origin "v$NOTCURSES_VERSION"
  git -C "$SRC_DIR" checkout "v$NOTCURSES_VERSION"
else
  echo "==> cloning notcurses v$NOTCURSES_VERSION"
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone --depth 1 --branch "v$NOTCURSES_VERSION" "$NOTCURSES_REPO" "$SRC_DIR"
fi

# Apply Cocoon's small input extension after checking out the pristine tag.
# --check keeps archive rebuilds deterministic and fails loudly if an upstream
# upgrade changes the parser context.
PASTE_PATCH="$PKG_ROOT/native/patches/notcurses-paste-events.patch"
if ! git -C "$SRC_DIR" diff --quiet -- include/notcurses/nckeys.h src/lib/in.c; then
  git -C "$SRC_DIR" checkout -- include/notcurses/nckeys.h src/lib/in.c
fi
git -C "$SRC_DIR" apply --check "$PASTE_PATCH"
git -C "$SRC_DIR" apply "$PASTE_PATCH"

# notcurses compiles its *-static targets with -fPIE (executable-style PIC).
# That is invalid for a static archive that gets --whole-archive'd into a
# SHARED library: aarch64's linker rejects it (R_AARCH64_ADR_PREL_PG_HI21
# "dangerous relocation" in menu/plot/progbar/reel/selector/tabbed). Flip the
# static targets to -fPIC. (x86-64 tolerates -fPIE here, so the linux_x64
# artifact happened to link; arm64 does not.)
PIC_PATCH="$PKG_ROOT/native/patches/notcurses-static-pic.patch"
git -C "$SRC_DIR" checkout -- CMakeLists.txt
git -C "$SRC_DIR" apply --check "$PIC_PATCH"
git -C "$SRC_DIR" apply "$PIC_PATCH"

BUILD_DIR="$SRC_DIR/build"
mkdir -p "$BUILD_DIR"

# ---- CMake configure --------------------------------------------------------
# Core-only: no FFmpeg multimedia, no C++/pandoc/pocs/executables/ffi lib.
CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DUSE_MULTIMEDIA=none
  -DUSE_PANDOC=OFF
  -DUSE_CXX=OFF
  -DBUILD_EXECUTABLES=OFF
  -DUSE_POC=OFF
  -DBUILD_FFI_LIBRARY=OFF
)

if [ "$HOST_OS" = "macos" ]; then
  HB="$(brew --prefix)"
  # Without the real (6.5+) ncurses on the pkg-config path, notcurses resolves
  # ncursesw to the old SDK shim (6.0) and fails the ncursesw>=6.1 check.
  export PKG_CONFIG_PATH="$HB/opt/ncurses/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  CMAKE_ARGS+=(
    -DCMAKE_OSX_ARCHITECTURES="$HOST_ARCH"
    -DCMAKE_PREFIX_PATH="$HB"
  )
fi

echo "==> cmake configure ($GEN)"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G "$GEN" "${CMAKE_ARGS[@]}"

echo "==> cmake build notcurses-core-static"
cmake --build "$BUILD_DIR" -j --target notcurses-core-static

# ---- stage libnotcurses-core.a ---------------------------------------------
CORE_A="$BUILD_DIR/libnotcurses-core.a"
[ -f "$CORE_A" ] || { echo "error: build did not produce $CORE_A" >&2; exit 1; }
mkdir -p "$OUT_DIR"
cp "$CORE_A" "$OUT_DIR/libnotcurses-core.a"
echo "==> staged $OUT_DIR/libnotcurses-core.a"

# ---- stage vendored macOS deps + licenses -----------------------------------
if [ "$HOST_OS" = "macos" ]; then
  HB="$(brew --prefix)"
  stage_dep() {  # <brew path> <out name>
    [ -f "$1" ] || { echo "error: missing brew archive: $1" >&2; \
                      echo "       brew install the dependency, then re-run." >&2; exit 1; }
    cp "$1" "$OUT_DIR/$2"
    echo "==> staged $OUT_DIR/$2"
  }
  stage_dep "$HB/opt/ncurses/lib/libncursesw.a" libncursesw.a
  stage_dep "$HB/lib/libunistring.a"            libunistring.a
  stage_dep "$HB/lib/libdeflate.a"              libdeflate.a

  # Refresh libunistring's LGPL license verbatim from the cellar (the ncurses
  # and libdeflate notices are hand-curated canonical text checked in under
  # LICENSES/ and do not need regenerating on every build).
  LIC="$OUT_DIR/LICENSES"
  mkdir -p "$LIC"
  cp "$HB/opt/libunistring/COPYING"     "$LIC/libunistring.COPYING"
  cp "$HB/opt/libunistring/COPYING.LIB" "$LIC/libunistring.COPYING.LIB"
  echo "==> refreshed libunistring license in $LIC"
fi

echo
echo "Done. Staged artifacts for ${HOST_OS}_${HOST_ARCH}:"
ls -1 "$OUT_DIR"/*.a
echo
echo "Next: from the package root, run 'dart test' (or dart run) to relink"
echo "notcurses_merged against these archives."
