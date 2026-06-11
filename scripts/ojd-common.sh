#!/usr/bin/env bash
# Shared constants and helpers for OpenJoystickDriver scripts.
# Source this file: source "$(dirname "$0")/ojd-common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment: legacy script-local files first, then central project files.
# Override with OJD_ENV=release or OJD_ENV=dev (default: dev)
OJD_ENV="${OJD_ENV:-dev}"
for _ENV_FILE in   "$SCRIPT_DIR/.env.$OJD_ENV"   "$PROJECT_DIR/.env"   "$PROJECT_DIR/.env.$OJD_ENV"
do
  if [[ -f "$_ENV_FILE" ]]; then
    set -a
    source "$_ENV_FILE"
    set +a
  fi
done
unset _ENV_FILE

# Prefer full Xcode toolchain when installed, even if `xcode-select` still
# points at Command Line Tools (avoids requiring sudo for local builds).
XCODE_SELECT_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$XCODE_SELECT_PATH" == "/Library/Developer/CommandLineTools" ]]; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode_26.3.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode_26.3.app/Contents/Developer"
  fi
fi
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  XCODE_SELECT_PATH="$DEVELOPER_DIR"
fi

# Workaround: xcrun --sdk hangs on macOS 26.3.1 (Xcode 26.3).
# Export SDKROOT so swift build, xcodebuild, and clang skip the xcrun lookup.
_DEFAULT_SDKROOT="$XCODE_SELECT_PATH/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -d "$_DEFAULT_SDKROOT" && -d "$XCODE_SELECT_PATH/SDKs/MacOSX.sdk" ]]; then
  _DEFAULT_SDKROOT="$XCODE_SELECT_PATH/SDKs/MacOSX.sdk"
fi
export SDKROOT="${SDKROOT:-$_DEFAULT_SDKROOT}"
unset _DEFAULT_SDKROOT
unset XCODE_SELECT_PATH

SWIFT_BIN="${SWIFT_BIN:-}"
if [[ -z "$SWIFT_BIN" ]]; then
  SWIFT_BIN="$(xcrun --find swift 2>/dev/null || command -v swift)"
fi

IDENTITY="${CODESIGN_IDENTITY:--}"
GUI_IDENTITY="${GUI_CODESIGN_IDENTITY:-$IDENTITY}"
DAEMON_IDENTITY="${DAEMON_CODESIGN_IDENTITY:-$IDENTITY}"
DAEMON_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriverDaemon"
GUI_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriver"
DAEMON_RELEASE="$PROJECT_DIR/.build/apple/Products/Release/OpenJoystickDriverDaemon"
GUI_RELEASE="$PROJECT_DIR/.build/apple/Products/Release/OpenJoystickDriver"

# Active binary paths (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  DAEMON_BIN="$DAEMON_RELEASE"
  GUI_BIN="$GUI_RELEASE"
else
  DAEMON_BIN="$DAEMON_DEBUG"
  GUI_BIN="$GUI_DEBUG"
fi

# Template paths (source-controlled, contain ${DEVELOPMENT_TEAM} placeholder)
GUI_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements.template"
DAEMON_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements.template"

# Resolved paths (generated at build time into .build/)
GUI_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriver.entitlements"
DAEMON_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriverDaemon.entitlements"

# ---------------------------------------------------------------------------
# Universal (fat) static libusb
# Homebrew only ships arm64 on Apple Silicon. For release builds we
# cross-compile x86_64 from source and lipo both slices into one .a
# so swift build links statically instead of against Homebrew's dylib.
# ---------------------------------------------------------------------------
LIBUSB_VERSION="1.0.29"
LIBUSB_CACHE_DIR="$PROJECT_DIR/.build/libusb-universal"
LIBUSB_UNIVERSAL_A="$LIBUSB_CACHE_DIR/lib/libusb-1.0.a"
LIBUSB_PC="$LIBUSB_CACHE_DIR/libusb-1.0.pc"

build_universal_libusb() {
  local SDK_PATH="$SDKROOT"
  echo "Building universal libusb ${LIBUSB_VERSION} (arm64 + x86_64)..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tarball="$tmpdir/libusb.tar.bz2"
  echo "  Downloading libusb ${LIBUSB_VERSION}..."
  curl -fsSL \
    "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2" \
    -o "$tarball"

  local ncpu
  ncpu="$(sysctl -n hw.ncpu)"

  echo "  Configuring arm64..."
  mkdir -p "$tmpdir/src-arm64"
  tar -xjf "$tarball" -C "$tmpdir/src-arm64" --strip-components=1
  (
    cd "$tmpdir/src-arm64"
    ./configure \
      CC="clang" \
      CFLAGS="-arch arm64 -target arm64-apple-macos10.15 -isysroot $SDK_PATH" \
      LDFLAGS="-arch arm64 -target arm64-apple-macos10.15" \
      --host=aarch64-apple-darwin \
      --prefix="$tmpdir/install-arm64" \
      --disable-shared --enable-static \
      --quiet 2>&1 | tail -5
    make -j"$ncpu" install --quiet
  )

  echo "  Configuring x86_64..."
  mkdir -p "$tmpdir/src-x86_64"
  tar -xjf "$tarball" -C "$tmpdir/src-x86_64" --strip-components=1
  (
    cd "$tmpdir/src-x86_64"
    ./configure \
      CC="clang" \
      CFLAGS="-arch x86_64 -target x86_64-apple-macos10.15 -isysroot $SDK_PATH" \
      LDFLAGS="-arch x86_64 -target x86_64-apple-macos10.15" \
      --host=x86_64-apple-darwin \
      --prefix="$tmpdir/install-x86_64" \
      --disable-shared --enable-static \
      --quiet 2>&1 | tail -5
    make -j"$ncpu" install --quiet
  )

  mkdir -p "$LIBUSB_CACHE_DIR/lib" "$LIBUSB_CACHE_DIR/include"
  lipo -create \
    "$tmpdir/install-arm64/lib/libusb-1.0.a" \
    "$tmpdir/install-x86_64/lib/libusb-1.0.a" \
    -output "$LIBUSB_UNIVERSAL_A"
  cp -r "$tmpdir/install-arm64/include/libusb-1.0" "$LIBUSB_CACHE_DIR/include/"

  echo "  Universal libusb ready: $(lipo -info "$LIBUSB_UNIVERSAL_A")"
}

setup_libusb_pkgconfig() {
  if [[ ! -f "$LIBUSB_UNIVERSAL_A" ]]; then
    build_universal_libusb
  else
    echo "Universal libusb cache hit: $LIBUSB_UNIVERSAL_A"
  fi

  cat > "$LIBUSB_PC" << EOF
prefix=$LIBUSB_CACHE_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libusb-1.0
Description: C API for USB device access (universal binary)
Version: $LIBUSB_VERSION
Libs: -L\${libdir} -lusb-1.0
Cflags: -I\${includedir}/libusb-1.0
EOF

  export PKG_CONFIG_PATH="$LIBUSB_CACHE_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
}

setup_sdl3_pkgconfig() {
  local sdl3_prefix="${OJD_SDL3_PREFIX:-$PROJECT_DIR/.build/sdl3}"
  local sdl3_pc="$sdl3_prefix/lib/pkgconfig/sdl3.pc"
  if [[ -f "$sdl3_pc" ]]; then
    export PKG_CONFIG_PATH="$sdl3_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export DYLD_LIBRARY_PATH="$sdl3_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    return 0
  fi

  if pkg-config --exists sdl3 2>/dev/null; then
    return 0
  fi

  echo "ERROR: SDL3 pkg-config metadata not found."
  echo "Fix: run: ./scripts/ojd install-sdl3"
  return 1
}

# Provisioning profiles (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  DAEMON_PROFILE="${DAEMON_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile}"
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
else
  DAEMON_PROFILE="${DAEMON_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile}"
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"
fi

# Verify that the provisioning profile's signing certificate matches the
# keychain identity. Fails with a clear message instead of letting AMFI
# reject the app at launch with error 163.
# Usage: verify_profile_cert <profile_path> <signing_identity>
decode_provisioning_profile() {
  local profile="$1"
  # Prefer Apple tooling when it works, but fall back to OpenSSL because
  # `security cms -D` can fail on some systems for `.provisionprofile`.
  if security cms -D -i "$profile" 2>/dev/null; then
    return 0
  fi
  openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null
}

verify_profile_cert() {
  local profile="$1" identity="$2"
  local profile_sha1 keychain_sha1
  local tmpder
  tmpder="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmpder'" RETURN

  # Extract first DeveloperCertificate from profile to a temp file
  # (binary DER data contains null bytes — can't store in bash variables)
  decode_provisioning_profile "$profile" \
    | plutil -extract DeveloperCertificates.0 raw -o - - \
    | base64 -d > "$tmpder" 2>/dev/null

  profile_sha1=$(openssl x509 -inform DER -in "$tmpder" -noout -fingerprint -sha1 2>/dev/null \
    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')

  keychain_sha1=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -i "$identity" | head -1 \
    | awk '{print $2}' | tr '[:upper:]' '[:lower:]')

  if [[ -z "$profile_sha1" || -z "$keychain_sha1" ]]; then
    echo "WARNING: Could not extract SHA1 for profile cert verification (profile_sha1=${profile_sha1:-empty}, keychain_sha1=${keychain_sha1:-empty})"
    return 0  # can't verify, don't block
  fi

  if [[ "$profile_sha1" != "$keychain_sha1" ]]; then
    echo ""
    echo "ERROR: Provisioning profile cert does not match signing identity!"
    echo ""
    echo "  profile: $profile"
    echo "  profile_cert_sha1: $profile_sha1"
    echo "  keychain_identity_sha1: $keychain_sha1"
    echo ""
    echo "Fix (no guessing):"
    echo "  1) Run: ./scripts/ojd signing doctor"
    echo "  2) Regenerate the provisioning profile selecting the certificate you have locally."
    echo "  3) Reinstall profiles: ./scripts/ojd signing install-profiles"
    echo "  4) Re-generate env:     ./scripts/ojd signing configure"
    echo ""
    return 1
  fi
}

# Sign binary with configured identity.
# Usage: ojd_sign <binary> [--entitlements <path>]
# NOTE: --entitlements must be the first extra arg pair (before any other flags).
# When OJD_ENV=release, adds hardened runtime (required for notarization).
ojd_sign() {
  local binary="$1"
  local identity="${OJD_ACTIVE_SIGN_IDENTITY:-$IDENTITY}"
  local extra_args=()
  if [[ "${2:-}" == "--entitlements" && -n "${3:-}" ]]; then
    extra_args=(--entitlements "$3")
  fi
  if [[ "$OJD_ENV" == "release" ]]; then
    extra_args+=(--options runtime --timestamp)
  fi
  codesign --sign "$identity" --force --generate-entitlement-der "${extra_args[@]+"${extra_args[@]}"}" "$binary"
}

ojd_sign_resource_bundle() {
  local bundle="$1"
  local identity="${OJD_ACTIVE_SIGN_IDENTITY:-$IDENTITY}"
  local extra_args=()
  if [[ "$OJD_ENV" == "release" ]]; then
    extra_args+=(--timestamp)
  fi
  codesign --sign "$identity" --force "${extra_args[@]+"${extra_args[@]}"}" "$bundle"
}

# Resolve entitlements templates: replace ${DEVELOPMENT_TEAM} with actual value.
# Usage: resolve_entitlements <template> <output>
resolve_entitlements() {
  local template="$1" output="$2"
  sed "s/\${DEVELOPMENT_TEAM}/$DEVELOPMENT_TEAM/g" "$template" > "$output"
}

_signed_entitlement_value() {
  local target="$1" key="$2"
  python3 - "$target" "$key" <<'PY'
import plistlib, subprocess, sys

target, key = sys.argv[1], sys.argv[2]
result = subprocess.run(
    ["codesign", "-d", "--entitlements", "-", "--xml", target],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)
if result.returncode != 0 or not result.stdout or b"<?xml" not in result.stdout:
    print("decode_error")
    raise SystemExit(0)

try:
    raw = result.stdout[result.stdout.index(b"<?xml") :]
    entitlements = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

value = entitlements.get(key, "missing")
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, str):
    print(value)
else:
    print("missing" if value == "missing" else str(value))
PY
}

_require_signed_entitlement_value() {
  local target="$1" key="$2" expected="$3" what="$4" fix="$5"
  local actual
  actual="$(_signed_entitlement_value "$target" "$key" || echo "missing")"
  if [[ "$actual" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not read signed entitlements from bundle."
    echo "  path: $target"
    echo "  affects: $what"
    echo ""
    echo "$fix"
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo ""
    echo "ERROR: Signed bundle entitlement value mismatch: $key"
    echo "  path: $target"
    echo "  affects: $what"
    echo "  expected: $expected"
    echo "  actual: $actual"
    echo ""
    echo "$fix"
    exit 1
  fi
}

verify_gui_app_signed_entitlements() {
  local target_app="$1"
  _require_signed_entitlement_value \
    "$target_app" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver" \
    "GUI app signed entitlements" \
    "Fix: regenerate GUI entitlements/provisioning, then rebuild."
  _require_signed_entitlement_value \
    "$target_app" \
    "com.apple.developer.hid.virtual.device" \
    "true" \
    "GUI app Compatibility backend" \
    "Fix: enable com.apple.developer.hid.virtual.device on the GUI profile, then rebuild."
}

verify_daemon_app_signed_entitlements() {
  local target_daemon="$1"
  _require_signed_entitlement_value \
    "$target_daemon" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver.daemon" \
    "Daemon app signed entitlements" \
    "Fix: regenerate daemon entitlements/provisioning, then rebuild."
  _require_signed_entitlement_value \
    "$target_daemon" \
    "com.apple.developer.hid.virtual.device" \
    "true" \
    "Daemon Compatibility backend" \
    "Fix: enable com.apple.developer.hid.virtual.device on the daemon profile, then rebuild."
}
