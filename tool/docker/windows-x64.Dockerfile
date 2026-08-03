# Reproducibly build the native/lib/windows_x64/ static archives by running the
# package's own tool/build_notcurses_windows_x64.sh inside MSYS2 UCRT64.
#
# Unlike linux-arm64.Dockerfile (a plain Debian cross-build), MSYS2/Windows
# artifacts can only be produced under MSYS2 itself. The official `msys2/msys2`
# image is a *Windows* container, so this Dockerfile must be built/run on a
# Windows Docker host (e.g. a GitHub Actions `windows-latest` runner, or a
# Windows machine with Docker Desktop in Windows-container mode). It does not
# build on a Linux Docker host.
#
# Example (on a Windows host with Docker in Windows-container mode):
#   docker build -t dart-notcurses-windows-x64 \
#     -f tool/docker/windows-x64.Dockerfile .
#   docker create --name tmp dart-notcurses-windows-x64
#   docker cp tmp:/work/native/lib/windows_x64 ./native/lib/
#   docker rm tmp
#
# Driven analogously to tool/build_notcurses_linux_arm64.sh.
FROM msys2/msys2:latest

ARG NOTCURSES_VERSION=3.0.17
ENV NOTCURSES_VERSION=${NOTCURSES_VERSION}

# Install the UCRT64 toolchain + notcurses build deps in the default (UCRT64-
# capable) MSYS2 environment. `winpty` is needed to invoke the UCRT64 shell
# non-interactively in some setups; git is required by the build script.
RUN pacman -S --noconfirm --needed \
        git mingw-w64-ucrt-x86_64-gcc \
        mingw-w64-ucrt-x86_64-cmake \
        mingw-w64-ucrt-x86_64-ninja \
        mingw-w64-ucrt-x86_64-pkg-config \
        mingw-w64-ucrt-x86_64-ncurses \
        mingw-w64-ucrt-x86_64-libunistring \
        mingw-w64-ucrt-x86_64-libdeflate \
        mingw-w64-ucrt-x86_64-winpthreads \
    && pacman -Scc --noconfirm

WORKDIR /work
# Copy the build script + patches only; the script clones notcurses itself.
COPY tool/build_notcurses_windows_x64.sh /work/tool/build_notcurses_windows_x64.sh
COPY native/patches                     /work/native/patches

# Run the build in the UCRT64 mingw environment. The script stages artifacts to
# /work/native/lib/windows_x64/.
RUN C:/msys64/usr/bin/bash.exe -lc \
    "MSYSTEM=UCRT64 /work/tool/build_notcurses_windows_x64.sh"
