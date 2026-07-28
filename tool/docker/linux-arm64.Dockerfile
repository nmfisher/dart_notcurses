# Cross-builds libnotcurses-core.a for linux/arm64 by running the package's
# own tool/build_notcurses.sh inside a native arm64 Debian container.
# On Apple Silicon this is native-speed (no QEMU); on Intel Mac it uses QEMU.
# Driven by tool/build_notcurses_linux_arm64.sh. The staged artifact lands at
# /work/native/lib/linux_arm64/libnotcurses-core.a and is copied out from there.
FROM debian:bookworm-slim

ARG NOTCURSES_VERSION=3.0.17
ENV NOTCURSES_VERSION=${NOTCURSES_VERSION}

# notcurses build deps: toolchain (build-essential pulls gcc/g++/binutils/`ar`,
# libc-dev) + cmake/ninja/pkg-config + the dev headers CMake's FindCurses and
# the optional-deflate path need at configure time. The transitive libs stay
# system shared libraries at final-link time (see hook/build.dart).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git cmake ninja-build pkg-config build-essential \
        libtinfo-dev libunistring-dev libdeflate-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
# Copy the build script + patch only; the script clones notcurses itself.
COPY tool/build_notcurses.sh /work/tool/build_notcurses.sh
COPY native/patches          /work/native/patches

RUN bash /work/tool/build_notcurses.sh
