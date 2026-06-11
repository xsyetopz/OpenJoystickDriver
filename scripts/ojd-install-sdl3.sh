#!/usr/bin/env bash
# Build and install the SDL3 revision required by OpenJoystickDriver.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

SDL3_REF="${OJD_SDL3_REF:-main}"
PREFIX="${OJD_SDL3_PREFIX:-$PROJECT_DIR/.build/sdl3}"
SRC_DIR="$PROJECT_DIR/.build/sdl3-src"
BUILD_DIR="$PROJECT_DIR/.build/sdl3-build"
SDL3_DYLIB="$PREFIX/lib/libSDL3.0.dylib"
REQUIRED_ARCHES=("arm64" "x86_64")

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd install-sdl3
  bash scripts/ojd-install-sdl3.sh [--github-env]

Environment:
  OJD_SDL3_REF      SDL git ref to build (default: main, currently SDL 3.5.0)
  OJD_SDL3_PREFIX   Install prefix (default: .build/sdl3)

Builds SDL3 from libsdl-org/SDL instead of Homebrew so CI/release can use the
current development version before Homebrew packages it.
USAGE
}

write_github_env=0
case "${1:-}" in
  "" )
    ;;
  "--github-env" )
    write_github_env=1
    ;;
  "-h"|"--help"|"help" )
    usage
    exit 0
    ;;
  * )
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

has_required_sdl3() {
  [[ -x "$PREFIX/bin/sdl3-config" && -f "$SDL3_DYLIB" ]] || return 1
  [[ "$("$PREFIX/bin/sdl3-config" --version)" == "3.5.0" ]] || return 1

  local arches
  arches="$(lipo -archs "$SDL3_DYLIB" 2>/dev/null || true)"
  for arch in "${REQUIRED_ARCHES[@]}"; do
    [[ " $arches " == *" $arch "* ]] || return 1
  done
}

if [[ -x "$PREFIX/bin/sdl3-config" ]]; then
  current_version="$("$PREFIX/bin/sdl3-config" --version)"
  if has_required_sdl3; then
    echo "SDL3 cache hit: $current_version at $PREFIX"
  fi
fi

if ! has_required_sdl3; then
  rm -rf "$SRC_DIR" "$BUILD_DIR" "$PREFIX"
  setup_libusb_pkgconfig
  git clone --depth 1 --branch "$SDL3_REF" https://github.com/libsdl-org/SDL.git "$SRC_DIR"
  cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_HIDAPI_LIBUSB_SHARED=OFF \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF
  cmake --build "$BUILD_DIR" --parallel
  cmake --install "$BUILD_DIR"
fi

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export DYLD_LIBRARY_PATH="$PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

echo "SDL3 version: $(pkg-config --modversion sdl3)"
echo "SDL3 prefix: $PREFIX"

if [[ "$write_github_env" == "1" ]]; then
  [[ -n "${GITHUB_ENV:-}" ]] || {
    echo "ERROR: --github-env requires GITHUB_ENV" >&2
    exit 2
  }
  {
    echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
  } >> "$GITHUB_ENV"
fi
