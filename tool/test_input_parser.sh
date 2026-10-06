#!/usr/bin/env bash
# Run after build_notcurses.sh, which prepares the source and generated headers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PKG_ROOT/native/.build/notcurses"
BUILD_DIR="$SRC_DIR/build"
if [ ! -f "$BUILD_DIR/include/builddef.h" ]; then
  echo "Run bash tool/build_notcurses.sh first." >&2
  exit 1
fi
case "$(uname -s)" in
  Darwin)
    HB="$(brew --prefix)"
    export PKG_CONFIG_PATH="$HB/opt/ncurses/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    LINK_FLAGS=(-Wl,-dead_strip -I"$HB/include" -L"$HB/lib" -lunistring)
    ;;
  Linux) LINK_FLAGS=(-Wl,--gc-sections -lunistring -lpthread -lm) ;;
  *) echo "Parser guard-page tests require macOS or Linux." >&2; exit 1 ;;
esac
DEP_FLAGS="$(pkg-config --cflags --libs ncursesw libdeflate)"
read -r -a DEPS <<< "$DEP_FLAGS"
"${CC:-cc}" -std=gnu11 -O1 -D_GNU_SOURCE -D_DEFAULT_SOURCE \
  -ffunction-sections -fdata-sections \
  -I"$SRC_DIR/include" -I"$SRC_DIR/src" -I"$BUILD_DIR/include" \
  "$PKG_ROOT/native/test/input_strings.c" "$BUILD_DIR/libnotcurses-core.a" \
  "${DEPS[@]}" "${LINK_FLAGS[@]}" -o "$BUILD_DIR/test_input_strings"
"$BUILD_DIR/test_input_strings"
