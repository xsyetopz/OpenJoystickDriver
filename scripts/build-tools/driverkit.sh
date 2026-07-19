# shellcheck shell=bash
# Generated DriverKit project, build, signing, embedding, and reproducibility owner.
set -euo pipefail

if [[ -z "${PROJECT_DIR:-}" ]]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../platform" && pwd)/environment.sh"
fi

DRIVERKIT_ROOT="$PROJECT_DIR/.build/driverkit"
DRIVERKIT_GENERATED="$DRIVERKIT_ROOT/generated"
DRIVERKIT_DERIVED_DATA="$DRIVERKIT_ROOT/derived-data"
DRIVERKIT_PROJECT="$DRIVERKIT_GENERATED/SwifterKitRuntime.xcodeproj"
DRIVERKIT_SCHEME="SwifterKitRuntime"
DRIVERKIT_BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
DRIVERKIT_PRODUCT_NAME="OpenJoystickVirtualHID"
DRIVERKIT_ENTITLEMENTS="$DRIVERKIT_GENERATED/SwifterKitRuntime.entitlements"
DRIVERKIT_REQUIRED_ENTITLEMENTS=(
  com.apple.developer.driverkit
  com.apple.developer.driverkit.family.hid.device
  com.apple.developer.driverkit.transport.hid
  com.apple.developer.driverkit.family.hid.eventservice
)
LEGACY_DRIVERKIT_USERCLIENT_VALUE=$'com.openjoystickdriver.VirtualHIDDevice\ncom.openjoystickdriver.daemon'

_legacy_driverkit_profile_enabled() {
  case "${OJD_USE_LEGACY_DRIVERKIT_PROFILE:-0}" in
    0) return 1 ;;
    1) ;;
    *) die "OJD_USE_LEGACY_DRIVERKIT_PROFILE must be 0 or 1" ;;
  esac
  [[ "$OJD_ENV" == "dev" ]] \
    || die "OJD_USE_LEGACY_DRIVERKIT_PROFILE=1 is forbidden for release builds"
  [[ "${CI:-false}" != "true" && "${CI:-0}" != "1" ]] \
    || die "OJD_USE_LEGACY_DRIVERKIT_PROFILE=1 is forbidden in CI"
  return 0
}

_warn_legacy_driverkit_profile() {
  [[ "${OJD_LEGACY_DRIVERKIT_WARNING_EMITTED:-0}" != "1" ]] || return 0
  OJD_LEGACY_DRIVERKIT_WARNING_EMITTED=1
  cat >&2 <<'TXT'
WARNING: The selected development profile contains Apple's approved legacy
DriverKit user-client value. The generated host entitlements omit
com.apple.developer.driverkit.userclient-access so macOS can launch the app.
Compatibility output remains available. DriverKit relay diagnostics are unavailable
until Apple approves the corrected single-relay grant and the profile is replaced.
TXT
}

_reject_local_swifterkit() {
  if [[ "${OJD_USE_LOCAL_SWIFTERKIT:-0}" == "1" ]] \
    && { [[ "$OJD_ENV" == "release" ]] || [[ "${CI:-false}" == "true" ]]; }; then
    die "OJD_USE_LOCAL_SWIFTERKIT=1 is forbidden in CI and release DriverKit builds"
  fi
}

_require_pinned_swifterkit() {
  [[ "${OJD_USE_LOCAL_SWIFTERKIT:-0}" != "1" ]] \
    || die "validate driverkit requires the resolved SwifterKit dependency"
}

_driverkit_versions() {
  DRIVERKIT_SHORT_VERSION="${OJD_BUNDLE_SHORT_VERSION:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}"
  DRIVERKIT_BUILD_VERSION="${DEXT_BUNDLE_VERSION:-${OJD_BUNDLE_VERSION:-1}}"
}

generate_driverkit_project() {
  local output="${1:-$DRIVERKIT_GENERATED}"
  _reject_local_swifterkit
  _driverkit_versions
  (
    cd "$PROJECT_DIR" || exit
    "$SWIFT_BUILD_BIN" --product DriverKitGenerator
    local generator_bin
    generator_bin="$($SWIFT_BUILD_BIN --show-bin-path)/DriverKitGenerator"
    [[ -x "$generator_bin" ]] || die "DriverKitGenerator executable was not built"
    "$generator_bin" \
      --output "$output" \
      --short-version "$DRIVERKIT_SHORT_VERSION" \
      --build-version "$DRIVERKIT_BUILD_VERSION"
  )
}

_validate_driverkit_metadata() {
  local tree="$1" short_version="$2" build_version="$3"
  python3 - "$tree" "$short_version" "$build_version" "$DRIVERKIT_BUNDLE_ID" <<'PY'
import plistlib
import sys
from pathlib import Path

tree, short_version, build_version, bundle_id = sys.argv[1:]
root = Path(tree)
info = plistlib.loads((root / "Info.plist").read_bytes())
entitlements = plistlib.loads((root / "SwifterKitRuntime.entitlements").read_bytes())
expected = {
    "com.apple.developer.driverkit",
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
}
if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
    raise SystemExit("generated plist does not delegate bundle identity to Xcode")
if info.get("CFBundleShortVersionString") != short_version:
    raise SystemExit("generated short version mismatch")
if info.get("CFBundleVersion") != build_version:
    raise SystemExit("generated build version mismatch")
personality = info.get("IOKitPersonalities", {}).get("SwiftDriver", {})
if personality.get("IOUserClass") != "SwifterKitRuntimeService":
    raise SystemExit("generated runtime service class mismatch")
if personality.get("IOUserServerName") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
    raise SystemExit("generated user-server identity mismatch")
if set(entitlements) != expected or any(entitlements[key] is not True for key in expected):
    raise SystemExit(f"generated DriverKit entitlements mismatch: {sorted(entitlements)}")
if "com.apple.developer.driverkit.allow-any-userclient-access" in entitlements:
    raise SystemExit("allow-any DriverKit user-client access is forbidden")
if bundle_id != "com.openjoystickdriver.VirtualHIDDevice":
    raise SystemExit("tooling bundle identity changed")
PY
}

_validate_driverkit_product() {
  local product="$1"
  python3 - "$product/Info.plist" "$DRIVERKIT_BUNDLE_ID" "$DRIVERKIT_PRODUCT_NAME" <<'PY'
import plistlib
import sys

path, bundle_id, product_name = sys.argv[1:]
info = plistlib.loads(open(path, "rb").read())
expected = {
    "CFBundleIdentifier": bundle_id,
    "CFBundleExecutable": product_name,
    "CFBundleName": product_name,
    "OSMinimumDriverKitVersion": "19.0",
}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f"built DriverKit metadata mismatch: {key}={info.get(key)!r}")
personality = info.get("IOKitPersonalities", {}).get("SwiftDriver", {})
if personality.get("IOUserClass") != "SwifterKitRuntimeService":
    raise SystemExit("built DriverKit service class mismatch")
if personality.get("IOUserServerName") != bundle_id:
    raise SystemExit("built DriverKit user-server identity mismatch")
PY
  [[ -x "$product/$DRIVERKIT_PRODUCT_NAME" ]] \
    || die "built DriverKit executable is missing"
}

_validate_entitlement_allowlist() {
  local plist="$1" key="$2" expected="$3"
  python3 - "$plist" "$key" "$expected" <<'PY'
import plistlib
import sys

path, key, expected = sys.argv[1:]
value = plistlib.loads(open(path, "rb").read()).get(key)
if value != [expected]:
    raise SystemExit(f"{path}: {key} must equal [{expected!r}], got {value!r}")
PY
}

_validate_host_entitlement_source() {
  local source="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Host.entitlements"
  _validate_entitlement_allowlist \
    "$source" com.apple.developer.driverkit.userclient-access "$DRIVERKIT_BUNDLE_ID"
  python3 - "$source" <<'PY'
import plistlib
import sys

entitlements = plistlib.loads(open(sys.argv[1], "rb").read())
if "com.apple.developer.driverkit.allow-any-userclient-access" in entitlements:
    raise SystemExit("authored host entitlements grant forbidden allow-any access")
PY
}

_require_host_access_profile() {
  local profile="$1" decoded="$DRIVERKIT_ROOT/profile-entitlements.plist"
  local mode="exact"
  if _legacy_driverkit_profile_enabled; then
    mode="legacy"
    _warn_legacy_driverkit_profile
  fi
  mkdir -p "$DRIVERKIT_ROOT"
  decode_provisioning_profile "$profile" > "$decoded" \
    || die "Could not decode GUI provisioning profile for DriverKit allowlist validation"
  python3 - \
    "$decoded" "$DRIVERKIT_BUNDLE_ID" "$mode" "$LEGACY_DRIVERKIT_USERCLIENT_VALUE" <<'PY'
import plistlib
import sys

profile, bundle_id, mode, legacy_value = sys.argv[1:]
entitlements = plistlib.loads(open(profile, "rb").read()).get("Entitlements", {})
value = entitlements.get("com.apple.developer.driverkit.userclient-access")
legacy = [legacy_value]
expected = legacy if mode == "legacy" else [bundle_id]
if value != expected:
    raise SystemExit(
        "GUI provisioning profile has an incorrect DriverKit user-client value: "
        f"expected {expected!r}, got {value!r}"
    )
if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("GUI provisioning profile grants forbidden allow-any DriverKit access")
PY
}

_resolve_host_entitlements() {
  local profile="$1" output="$2"
  _require_host_access_profile "$profile"
  resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$output"
  if ! _legacy_driverkit_profile_enabled; then
    return 0
  fi

  python3 - "$output" <<'PY'
import plistlib
import sys

output_path = sys.argv[1]
output = plistlib.loads(open(output_path, "rb").read())
output.pop("com.apple.developer.driverkit.userclient-access", None)
with open(output_path, "wb") as file:
    plistlib.dump(output, file, sort_keys=False)
PY
}

_require_driverkit_profile() {
  local profile="$1" decoded="$DRIVERKIT_ROOT/dext-profile-entitlements.plist"
  mkdir -p "$DRIVERKIT_ROOT"
  decode_provisioning_profile "$profile" > "$decoded" \
    || die "Could not decode DriverKit provisioning profile"
  python3 - "$decoded" <<'PY'
import plistlib
import sys

entitlements = plistlib.loads(open(sys.argv[1], "rb").read()).get("Entitlements", {})
required = {
    "com.apple.developer.driverkit",
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
}
missing = sorted(key for key in required if entitlements.get(key) is not True)
if missing:
    raise SystemExit(f"DriverKit provisioning profile is missing entitlements: {missing}")
if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("DriverKit provisioning profile grants forbidden allow-any access")
PY
}

_require_signed_host_access() {
  local app="$1" profile="$2"
  local decoded="$DRIVERKIT_ROOT/signed-app-entitlements.plist"
  local decoded_profile="$DRIVERKIT_ROOT/signed-app-profile.plist"
  _require_host_access_profile "$profile"
  codesign -d --entitlements - --xml "$app" > "$decoded" 2>/dev/null \
    || die "Could not read signed app entitlements"
  decode_provisioning_profile "$profile" > "$decoded_profile" \
    || die "Could not decode GUI provisioning profile for signed entitlement validation"
  local mode="exact"
  if _legacy_driverkit_profile_enabled; then
    mode="legacy"
  fi
  python3 - "$decoded" "$decoded_profile" "$mode" <<'PY'
import plistlib
import sys

signed_path, profile_path, mode = sys.argv[1:]
signed = plistlib.loads(open(signed_path, "rb").read())
profile = plistlib.loads(open(profile_path, "rb").read()).get("Entitlements", {})
key = "com.apple.developer.driverkit.userclient-access"
if mode == "legacy" and key in signed:
    raise SystemExit(
        f"legacy development host must omit {key}, got {signed.get(key)!r}"
    )
if mode == "exact" and signed.get(key) != profile.get(key):
    raise SystemExit(
        f"signed host {key} does not match the selected profile: "
        f"signed={signed.get(key)!r}, profile={profile.get(key)!r}"
    )
if signed.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("signed app grants forbidden allow-any DriverKit access")
PY
}

_require_signed_driverkit_entitlements() {
  local dext="$1" decoded="$DRIVERKIT_ROOT/signed-dext-entitlements.plist"
  codesign -d --entitlements - --xml "$dext" > "$decoded" 2>/dev/null \
    || die "Could not read signed DriverKit entitlements"
  python3 - "$decoded" <<'PY'
import plistlib
import sys

value = plistlib.loads(open(sys.argv[1], "rb").read())
required = {
    "com.apple.developer.driverkit",
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
}
actual = {key for key, item in value.items() if item is True and key in required}
if actual != required:
    raise SystemExit(f"signed DriverKit entitlements mismatch: {sorted(value)}")
if value.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("signed dext grants forbidden allow-any DriverKit access")
PY
}

_driverkit_xcodebuild() {
  local configuration="$1"
  shift
  xcodebuild \
    -project "$DRIVERKIT_PROJECT" \
    -scheme "$DRIVERKIT_SCHEME" \
    -configuration "$configuration" \
    -derivedDataPath "$DRIVERKIT_DERIVED_DATA" \
    PRODUCT_BUNDLE_IDENTIFIER="$DRIVERKIT_BUNDLE_ID" \
    PRODUCT_NAME="$DRIVERKIT_PRODUCT_NAME" \
    EXECUTABLE_NAME="$DRIVERKIT_PRODUCT_NAME" \
    DRIVERKIT_DEPLOYMENT_TARGET=19.0 \
    "$@" clean build
}

build_dext_bundle() {
  [[ "${CODESIGN_IDENTITY:--}" != "-" ]] \
    || die "DriverKit extensions cannot use ad-hoc signing; run ./scripts/ojd signing configure"
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] \
    || die "DEVELOPMENT_TEAM not set; run ./scripts/ojd signing configure"
  local configuration="Debug"
  [[ "$OJD_ENV" == "release" ]] && configuration="Release"
  local profile="${DEXT_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
  [[ -f "$profile" ]] || die "DriverKit provisioning profile not found: $profile"
  _require_driverkit_profile "$profile"

  rm -rf "$DRIVERKIT_GENERATED" "$DRIVERKIT_DERIVED_DATA"
  generate_driverkit_project
  _validate_driverkit_metadata \
    "$DRIVERKIT_GENERATED" "$DRIVERKIT_SHORT_VERSION" "$DRIVERKIT_BUILD_VERSION"

  local identity="${DEXT_BUILD_IDENTITY:-$CODESIGN_IDENTITY}"
  local profile_name="${DEXT_BUILD_PROFILE:-OpenJoystickDriver (VirtualHIDDevice)}"
  verify_profile_cert "$profile" "$identity"
  local signing=(
    CODE_SIGN_IDENTITY="$identity"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    PROVISIONING_PROFILE_SPECIFIER="$profile_name"
    CODE_SIGN_STYLE=Manual
  )
  if [[ "$OJD_ENV" == "release" ]]; then
    signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi
  _driverkit_xcodebuild "$configuration" "${signing[@]}"

  local product="$DRIVERKIT_DERIVED_DATA/Build/Products/${configuration}-driverkit/${DRIVERKIT_PRODUCT_NAME}.dext"
  [[ -d "$product" ]] || die "generated DriverKit product not found: $product"
  _validate_driverkit_product "$product"
  local app="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  [[ -d "$app" ]] || die "app bundle not found; run ./scripts/ojd build dev first"
  local embedded="$app/Contents/Library/SystemExtensions/${DRIVERKIT_BUNDLE_ID}.dext"
  mkdir -p "$(dirname "$embedded")"
  rm -rf "$embedded"
  cp -R "$product" "$embedded"
  cp "$profile" "$embedded/embedded.provisionprofile"

  local sign_args=(--force --sign "$identity" --generate-entitlement-der --entitlements "$DRIVERKIT_ENTITLEMENTS")
  [[ "$OJD_ENV" == "release" ]] && sign_args+=(--options runtime --timestamp)
  codesign "${sign_args[@]}" "$embedded"
  _require_signed_driverkit_entitlements "$embedded"

  _resolve_host_entitlements "$GUI_PROFILE" "$GUI_ENTITLEMENTS"
  sign_args=(--force --sign "$GUI_IDENTITY" --generate-entitlement-der --entitlements "$GUI_ENTITLEMENTS")
  [[ "$OJD_ENV" == "release" ]] && sign_args+=(--options runtime --timestamp)
  codesign "${sign_args[@]}" "$app"
  _require_signed_host_access "$app" "$GUI_PROFILE"

  if [[ "${OJD_SKIP_INSTALL:-0}" != "1" ]]; then
    rm -rf /Applications/OpenJoystickDriver.app
    cp -R "$app" /Applications/
  fi
  echo "DriverKit extension built and embedded: $embedded"
}

validate_driverkit() {
  _require_pinned_swifterkit
  _driverkit_versions
  local first="$DRIVERKIT_ROOT/validation-one"
  local second="$DRIVERKIT_ROOT/validation-two"
  rm -rf "$first" "$second" "$DRIVERKIT_DERIVED_DATA"
  generate_driverkit_project "$first"
  generate_driverkit_project "$second"
  diff -qr "$first" "$second" >/dev/null \
    || die "two fresh SwifterKit generations are not byte-for-byte identical"
  _validate_driverkit_metadata "$first" "$DRIVERKIT_SHORT_VERSION" "$DRIVERKIT_BUILD_VERSION"
  if generate_driverkit_project "$first" >/dev/null 2>&1; then
    die "generator overwrote an existing destination"
  fi

  local tracked_native
  tracked_native="$(
    git ls-files | grep -E '^(DriverKitExtension/|\.build/driverkit/|.*\.(iig|cpp|hpp)$)' \
      | while IFS= read -r path; do
          [[ ! -e "$PROJECT_DIR/$path" ]] || printf '%s\n' "$path"
        done
  )"
  if [[ -n "$tracked_native" ]]; then
    die "tracked manual or generated DriverKit artifacts remain"
  fi
  grep -q 'name: "DriverKitGenerator"' "$PROJECT_DIR/Package.swift" \
    || die "DriverKitGenerator target is missing"
  ! rg -l '^import SwifterKit$' "$PROJECT_DIR/Sources/OpenJoystickDriverKit" >/dev/null \
    || die "OpenJoystickDriverKit must not import SwifterKit"
  python3 - "$PROJECT_DIR/Sources" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
allowed = {"DriverKitGenerator", "OpenJoystickDriverRelay"}
violations = []
for path in root.rglob("*.swift"):
    if "import SwifterKit" in path.read_text() and path.relative_to(root).parts[0] not in allowed:
        violations.append(str(path.relative_to(root)))
if violations:
    raise SystemExit(f"SwifterKit import boundary violated: {violations}")
PY
  _validate_host_entitlement_source
  python3 - "$PROJECT_DIR/Package.resolved" <<'PY'
import json
import sys

pins = json.load(open(sys.argv[1]))["pins"]
pin = next((item for item in pins if item["identity"] == "swifterkit"), None)
expected = {
    "location": "https://github.com/xsyetopz/SwifterKit.git",
    "branch": "main",
    "revision": "564a77c050561c286ba81198ad56518dad069c17",
}
actual = None if pin is None else {
    "location": pin.get("location"),
    "branch": pin.get("state", {}).get("branch"),
    "revision": pin.get("state", {}).get("revision"),
}
if actual != expected:
    raise SystemExit(f"Package.resolved SwifterKit pin mismatch: {actual!r}")
PY

  DRIVERKIT_GENERATED="$first"
  DRIVERKIT_PROJECT="$first/SwifterKitRuntime.xcodeproj"
  DRIVERKIT_ENTITLEMENTS="$first/SwifterKitRuntime.entitlements"
  _driverkit_xcodebuild Debug \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
  local product="$DRIVERKIT_DERIVED_DATA/Build/Products/Debug-driverkit/${DRIVERKIT_PRODUCT_NAME}.dext"
  _validate_driverkit_product "$product"
  local architectures
  architectures="$(lipo -archs "$product/$DRIVERKIT_PRODUCT_NAME")"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] \
    || die "installed DriverKit SDK did not produce arm64 and x86_64 slices: $architectures"
  echo "DriverKit generation, architecture, and unsigned universal build validation passed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    generate)
      shift
      [[ $# -le 1 ]] || die "driverkit generate accepts at most one output path"
      output="${1:-$DRIVERKIT_GENERATED}"
      [[ "$output" == /* ]] || output="$PWD/$output"
      generate_driverkit_project "$output"
      ;;
    validate)
      shift
      [[ $# -eq 0 ]] || die "validate driverkit does not accept arguments"
      validate_driverkit
      ;;
    *) die "expected generate [output] or validate" ;;
  esac
fi
