#!/bin/sh
# Regenerate the ffigen bindings from the vendored headers and shim.
#
#   lib/src/ffi/notcurses_g.dart        <- ffi/notcurses.yml  <- native/include/notcurses/*.h
#   lib/src/ffi/notcurses_inline_g.dart <- ffi/inline.yml     <- native/src/ffi.c
#
# Everything is generated from the sources vendored in this repo — never from
# a system notcurses install. No post-processing; the output is final.
# Run after changing native/include headers or adding declarations to
# native/src/ffi.c.
set -eu
cd "$(dirname "$0")/.."

dart run ffigen --config ffi/notcurses.yml
dart run ffigen --config ffi/inline.yml

# The wrapper layer must still type-check against the fresh bindings.
dart analyze
