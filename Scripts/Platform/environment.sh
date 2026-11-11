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

# The installed app executable, the only command line the repository scripts run.
OJD_APP_CLI="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"

# Stop with an error when the installed app executable is missing.
require_ojd_app_cli() {
  [[ -x "$OJD_APP_CLI" ]] ||
    die "OpenJoystickDriver is not installed at $OJD_APP_CLI; run ./Scripts/ojd build install dev"
}

# Run the app executable as the `ojd` command line, which it selects by argv[0].
# The function replaces its shell, so call it in a subshell: `(ojd_cli ...)`, `$(ojd_cli ...)`,
# or `ojd_cli ... &`. Usage: ojd_cli <executable> <arguments...>
ojd_cli() {
  local executable="$1"
  shift
  exec -a ojd "$executable" "$@"
}

# Load exactly one repository-local environment file.
# OJD_ENV selects .env.dev (default) or .env.release at the project root.
OJD_ENV="${OJD_ENV:-dev}"
case "$OJD_ENV" in
  dev|release) ;;
  *) echo "ERROR: OJD_ENV must be dev or release (got: $OJD_ENV)" >&2; return 1 ;;
esac
OJD_ENV_FILE="$PROJECT_DIR/.env.$OJD_ENV"
if [[ -f "$OJD_ENV_FILE" ]]; then
  # env_file.py stops on a key that no script reads; the first run reports it, because the exit
  # status of the process substitution below is lost.
  python3 "$LIB_DIR/env_file.py" read "$OJD_ENV_FILE" >/dev/null || exit 2
  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    export "$key=$value"
  done < <(python3 "$LIB_DIR/env_file.py" read "$OJD_ENV_FILE")
fi

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

# Every Swift command runs the swift of the selected Xcode, so one compiler writes `.build`. The
# swift.org toolchains from 6.0.1 on build their runtime for macOS 13, so linking a macOS 12
# target against them warns; Xcode's toolchain links against the SDK instead.
export PATH="$XCODE_SELECT_PATH/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
SWIFT_PATH="$(command -v swift)" || die "swift is not on PATH"
_SWIFT_PINNED="$(tr -d '[:space:]' < "$PROJECT_DIR/.swift-version")"
_SWIFT_FOUND="$("$SWIFT_PATH" --version 2>&1 |
  sed -nE 's/.*Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -n1)"
[[ "$_SWIFT_FOUND" == *.*.* ]] || _SWIFT_FOUND="$_SWIFT_FOUND.0"
# `.swift-version` names the oldest Swift that builds for the macOS 12 floor.
[[ "$(printf '%s\n%s\n' "$_SWIFT_PINNED" "$_SWIFT_FOUND" | sort -V | head -n1)" == "$_SWIFT_PINNED" ]] ||
  die "$SWIFT_PATH is Swift $_SWIFT_FOUND; .swift-version needs $_SWIFT_PINNED or newer: select a newer Xcode with DEVELOPER_DIR"
unset _SWIFT_PINNED _SWIFT_FOUND

# Export SDKROOT so swift build, xcodebuild, and clang skip the xcrun lookup, which can hang, and
# use the selected Xcode SDK instead of the CommandLineTools SDK.
# The SDK must be one that swift can read: a swift older than the selected Xcode's gets the
# newest installed SDK it reads, with a note; an explicit SDKROOT it cannot read is an error.
_DEFAULT_SDKROOT="$XCODE_SELECT_PATH/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -d "$_DEFAULT_SDKROOT" && -d "$XCODE_SELECT_PATH/SDKs/MacOSX.sdk" ]]; then
  _DEFAULT_SDKROOT="$XCODE_SELECT_PATH/SDKs/MacOSX.sdk"
fi
_SDKROOT_EXPLICIT=0
[[ -n "${SDKROOT:-}" ]] && _SDKROOT_EXPLICIT=1
SDKROOT="$(python3 "$LIB_DIR/swift_sdk.py" "$SWIFT_PATH" "${SDKROOT:-$_DEFAULT_SDKROOT}" \
  "$_SDKROOT_EXPLICIT")" || die "no macOS SDK fits $SWIFT_PATH"
export SDKROOT
unset _DEFAULT_SDKROOT _SDKROOT_EXPLICIT
unset XCODE_SELECT_PATH

# One identity signs the app, its resource bundles and the DEXT: `signing configure` picks the
# identity that every profile of the mode embeds. Unset, the app is signed ad hoc (`-`).
IDENTITY="${CODESIGN_IDENTITY:--}"
export GUI_PROJECT="$PROJECT_DIR/OpenJoystickDriver.xcodeproj"
export GUI_SCHEME="OpenJoystickDriverApp"
export GUI_DERIVED_DATA="$PROJECT_DIR/.build/xcode"
OJD_APP_INFO_PLIST="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Info.plist"
OJD_DEFAULT_BUNDLE_SHORT_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$OJD_APP_INFO_PLIST" 2>/dev/null)"
if [[ ! "$OJD_DEFAULT_BUNDLE_SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  die "CFBundleShortVersionString in $OJD_APP_INFO_PLIST must be SemVer without build metadata"
fi

# Template paths (source-controlled, contain ${DEVELOPMENT_TEAM} placeholder)
GUI_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Host.entitlements"
export GUI_ENTITLEMENTS_TEMPLATE

# Resolved paths (generated at build time into .build/)
GUI_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriver.entitlements"
export GUI_ENTITLEMENTS

# Provisioning profiles (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
else
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"
fi
export GUI_PROFILE

# Verify that the keychain identity's certificate is one of the certificates
# embedded in the provisioning profile. Fails with a clear message instead of letting AMFI
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
  local profile_sha1s="" keychain_sha1 profile_plist
  local tmpdir index sha1 cert_b64
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  profile_plist="$tmpdir/profile.plist"

  if ! decode_provisioning_profile "$profile" > "$profile_plist" || [[ ! -s "$profile_plist" ]]; then
    echo "ERROR: Could not decode provisioning profile: $profile"
    return 1
  fi

  # A profile embeds every certificate it was generated for. Collect the SHA1 of each.
  # Binary DER data contains null bytes, so it goes through temp files.
  index=0
  while cert_b64=$(plutil -extract "DeveloperCertificates.$index" raw -o - "$profile_plist" 2>/dev/null); do
    printf '%s' "$cert_b64" | base64 -d > "$tmpdir/cert.der" 2>/dev/null
    sha1=$(openssl x509 -inform DER -in "$tmpdir/cert.der" -noout -fingerprint -sha1 2>/dev/null \
      | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
    if [[ -z "$sha1" ]]; then
      echo "ERROR: Could not read DeveloperCertificates.$index of profile: $profile"
      return 1
    fi
    profile_sha1s+="$sha1 "
    index=$((index + 1))
  done

  keychain_sha1=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -i -F "$identity" | head -1 \
    | awk '{print $2}' | tr '[:upper:]' '[:lower:]')

  if [[ -z "$profile_sha1s" || -z "$keychain_sha1" ]]; then
    echo ""
    echo "ERROR: Could not verify the provisioning profile certificate against the signing identity."
    echo ""
    echo "  profile: $profile"
    echo "  profile_cert_sha1s: ${profile_sha1s:-none}"
    echo "  keychain_identity_sha1: ${keychain_sha1:-none}"
    echo "  identity: $identity"
    echo ""
    echo "Repair:"
    echo "  1) Unlock the login keychain and check: security find-identity -v -p codesigning"
    echo ""
    return 1
  fi

  if [[ " $profile_sha1s" != *" $keychain_sha1 "* ]]; then
    echo ""
    echo "ERROR: Provisioning profile certs do not include the signing identity!"
    echo ""
    echo "  profile: $profile"
    echo "  profile_cert_sha1s: $profile_sha1s"
    echo "  keychain_identity_sha1: $keychain_sha1"
    echo ""
    echo "Repair:"
    echo "  1) Regenerate the provisioning profile selecting the certificate you have locally."
    echo "  2) Reinstall profiles: ./Scripts/ojd signing install-profiles"
    echo "  3) Re-generate env:     ./Scripts/ojd signing configure"
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
    root = plistlib.loads(sys.stdin.buffer.read())
except plistlib.InvalidFileException:
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

# Apple Development host designated requirement: bundle id + team OU.
# Leading "=" is required so codesign treats this as source, not a file path.
# Do not pin cdhash or leaf CN: TCC Input Monitoring / Accessibility keys off
# this requirement, and a unique pin goes stale on every re-sign.
ojd_host_designated_requirement() {
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    die "DEVELOPMENT_TEAM not set (needed for a stable host designated requirement)"
  fi
  printf '=designated => identifier "com.openjoystickdriver" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.1] exists and certificate leaf[subject.OU] = "%s"' \
    "$DEVELOPMENT_TEAM"
}

# Sign binary with configured identity.
# Usage: ojd_sign <binary> [--entitlements <path>]
# NOTE: --entitlements must be the first extra arg pair (before any other flags).
# When OJD_ENV=release, adds hardened runtime (required for notarization).
# Development host signing embeds ojd_host_designated_requirement so same-team
# rebuilds keep TCC grants. Release keeps codesign's Developer ID default DR.
ojd_sign() {
  local binary="$1"
  local identity="$IDENTITY"
  local extra_args=()
  if [[ "${2:-}" == "--entitlements" && -n "${3:-}" ]]; then
    extra_args=(--entitlements "$3")
  fi
  if [[ "$OJD_ENV" == "release" ]]; then
    extra_args+=(--options runtime --timestamp)
  else
    extra_args+=(--requirements "$(ojd_host_designated_requirement)")
  fi
  codesign --sign "$identity" --force --generate-entitlement-der "${extra_args[@]+"${extra_args[@]}"}" "$binary"
}

ojd_sign_resource_bundle() {
  local bundle="$1"
  local identity="$IDENTITY"
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
