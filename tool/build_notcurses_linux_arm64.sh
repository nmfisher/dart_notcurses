#!/usr/bin/env bash
#
# Cross-build libnotcurses-core.a for linux/arm64 from any host with Docker,
# by running tool/build_notcurses.sh inside a native linux/arm64 Debian
# container, then copying the staged artifact into native/lib/linux_arm64/.
#
# The build runs in the image's own filesystem (no bind-mount), so it never
# touches the host's existing native/.build/notcurses checkout/build dir.
#
# Usage:
#   ./tool/build_notcurses_linux_arm64.sh
#   NOTCURSES_VERSION=3.0.17 ./tool/build_notcurses_linux_arm64.sh
#
# Requirements: Docker (Desktop/OrbStack/Rancher). On Apple Silicon the
# linux/arm64 container runs natively; on Intel Mac it is QEMU-emulated.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$PKG_ROOT/native/lib/linux_arm64"
IMAGE_TAG="dart-notcurses-linux-arm64:latest"
VERSION="${NOTCURSES_VERSION:-3.0.17}"

command -v docker >/dev/null 2>&1 || {
  echo "error: docker not found in PATH" >&2
  exit 1
}

echo "==> building linux/arm64 image (notcurses v$VERSION)"
docker build --platform linux/arm64 \
  --build-arg NOTCURSES_VERSION="$VERSION" \
  -t "$IMAGE_TAG" \
  -f "$SCRIPT_DIR/docker/linux-arm64.Dockerfile" \
  "$PKG_ROOT"

mkdir -p "$OUT_DIR"
cid="$(docker create --platform linux/arm64 "$IMAGE_TAG")"
trap 'docker rm "$cid" >/dev/null' EXIT

echo "==> extracting libnotcurses-core.a"
docker cp "$cid:/work/native/lib/linux_arm64/libnotcurses-core.a" \
  "$OUT_DIR/libnotcurses-core.a"

echo "==> staged $OUT_DIR/libnotcurses-core.a"
