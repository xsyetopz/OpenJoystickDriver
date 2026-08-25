#!/usr/bin/env bash
# macOS toolchain, environment, and signing contract for repository scripts.
# Source this file from an implementation script; do not execute it directly.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$LIB_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

# Load exactly one repository-local environment file.
# OJD_ENV selects .env.dev (default) or .env.release at the project root.
OJD_ENV="${OJD_ENV:-dev}"
case "$OJD_ENV" in
  dev|release) ;;
  *) echo "ERROR: OJD_ENV must be dev or release (got: $OJD_ENV)" >&2; return 1 2>/dev/null || exit 1 ;;
esac
OJD_ENV_FILE="$PROJECT_DIR/.env.$OJD_ENV"
if [[ -f "$OJD_ENV_FILE" ]]; then
  set -a
  source "$OJD_ENV_FILE"
  set +a
fi
export OJD_ENV_FILE

# Prefer full Xcode toolchain when installed, even if `xcode-select` still
# points at Command Line Tools (avoids requiring sudo for local builds).
XCODE_SELECT_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$XCODE_SELECT_PATH" == "/Library/Developer/CommandLineTools" ]]; then
  # Select the newest installed Xcode without requiring sudo or a fixed version.
  latest_xcode=""
  while IFS= read -r candidate; do
    if [[ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]]; then
      latest_xcode="$candidate"
      break
    fi
  done < <(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null | sort -r)
  if [[ -n "$latest_xcode" ]]; then
    export DEVELOPER_DIR="$latest_xcode/Contents/Developer"
  fi
  unset latest_xcode
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
SWIFT_BUILD_BIN="${SWIFT_BUILD_BIN:-$(xcrun --find swift-build 2>/dev/null || command -v swift-build)}"
SWIFT_PACKAGE_BIN="${SWIFT_PACKAGE_BIN:-$(xcrun --find swift-package 2>/dev/null || command -v swift-package)}"

IDENTITY="${CODESIGN_IDENTITY:--}"
GUI_IDENTITY="${GUI_CODESIGN_IDENTITY:-$IDENTITY}"
GUI_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriver"
GUI_RELEASE="$PROJECT_DIR/.build/apple/Products/Release/OpenJoystickDriver"
OJD_APP_INFO_PLIST="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Info.plist"
OJD_DEFAULT_BUNDLE_SHORT_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$OJD_APP_INFO_PLIST" 2>/dev/null)"
if [[ ! "$OJD_DEFAULT_BUNDLE_SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$ ]]; then
  die "Invalid or missing CFBundleShortVersionString in $OJD_APP_INFO_PLIST"
fi

# Active binary paths (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  GUI_BIN="$GUI_RELEASE"
else
  GUI_BIN="$GUI_DEBUG"
fi

# Template paths (source-controlled, contain ${DEVELOPMENT_TEAM} placeholder)
GUI_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Host.entitlements"

# Resolved paths (generated at build time into .build/)
GUI_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriver.entitlements"

# Provisioning profiles (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
else
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

verify_profile_cert() (
  local profile="$1" identity="$2"
  local profile_sha1 keychain_sha1
  local tmpder
  tmpder="$(mktemp)"
  trap 'rm -f "$tmpder"' EXIT

  # Extract first DeveloperCertificate from profile to a temp file
  # Binary DER data contains null bytes, so it cannot be stored in Bash variables.
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
    echo "Repair:"
    echo "  1) Run: ./scripts/ojd signing doctor"
    echo "  2) Regenerate the provisioning profile selecting the certificate you have locally."
    echo "  3) Reinstall profiles: ./scripts/ojd signing install-profiles"
    echo "  4) Re-generate env:     ./scripts/ojd signing configure"
    echo ""
    return 1
  fi
)

# The restricted DriverKit extension is eligible to start only when one of the
# Apple-approved Microsoft GIP interfaces is present. Third-party GIP devices
# remain on the app-owned IOUSBHost path.
ojd_microsoft_driverkit_interface_connected() {
  ioreg -r -c IOUSBHostInterface -a 2>/dev/null | python3 -c '
import plistlib
import sys

products = {0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12}

def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)

try:
    root = plistlib.load(sys.stdin.buffer)
except Exception:
    raise SystemExit(1)

for item in dictionaries(root):
    if (
        item.get("idVendor") == 0x045E
        and item.get("idProduct") in products
        and item.get("bConfigurationValue") == 1
        and item.get("bInterfaceNumber") == 0
        and item.get("bInterfaceClass") == 0xFF
        and item.get("bInterfaceSubClass") == 0x47
        and item.get("bInterfaceProtocol") == 0xD0
    ):
        raise SystemExit(0)
raise SystemExit(1)
'
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
