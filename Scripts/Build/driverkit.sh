# shellcheck shell=bash
# Generated DriverKit project, build, signing, embedding, and reproducibility owner.
set -euo pipefail

if [[ -z "${PROJECT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/../Platform/environment.sh"
fi

DRIVERKIT_ROOT="$PROJECT_DIR/.build/driverkit"
DRIVERKIT_SCHEME="SwifterKitRuntime"
DRIVERKIT_BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
DRIVERKIT_PRODUCT_NAME="VirtualHIDDevice"
DRIVERKIT_GENERATED="$DRIVERKIT_ROOT/generated"
DRIVERKIT_DERIVED_DATA="$DRIVERKIT_ROOT/derived-data"
DRIVERKIT_PROJECT="$DRIVERKIT_GENERATED/SwifterKitRuntime.xcodeproj"
DRIVERKIT_PROFILE_SPECIFIER="${DEXT_BUILD_PROFILE:-OpenJoystickDriver (VirtualHIDDevice)}"
DRIVERKIT_AUTHORED_ENTITLEMENTS="$PROJECT_DIR/Sources/DriverKitGenerator/Entitlements/${DRIVERKIT_PRODUCT_NAME}.entitlements"
DRIVERKIT_SIGNING_ENTITLEMENTS="$DRIVERKIT_AUTHORED_ENTITLEMENTS"
_driverkit_profile_suffix=""
[[ "${OJD_ENV:-dev}" == "release" ]] && _driverkit_profile_suffix="_DevID"
DRIVERKIT_DEFAULT_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_${DRIVERKIT_PRODUCT_NAME}${_driverkit_profile_suffix}.provisionprofile"
DRIVERKIT_PROFILE="${DEXT_PROVISIONING_PROFILE:-$DRIVERKIT_DEFAULT_PROFILE}"
# 1 builds the USB personality, which needs Apple's transport.usb grant for this bundle ID. A
# signed build follows the profile; generation and validation build it unless
# OJD_DRIVERKIT_WITHOUT_USB=1.
DRIVERKIT_INCLUDE_USB=1
[[ "${OJD_DRIVERKIT_WITHOUT_USB:-0}" == "1" ]] && DRIVERKIT_INCLUDE_USB=0

# Mirrors Package.swift: the sibling checkout is used only when OJD_USE_LOCAL_SWIFTERKIT=1.
_swifterkit_is_local() {
  [[ "${OJD_USE_LOCAL_SWIFTERKIT:-}" == "1" ]] && [[ -d "$PROJECT_DIR/../SwifterKit" ]]
}

_reject_local_swifterkit() {
  if _swifterkit_is_local \
    && { [[ "$OJD_ENV" == "release" ]] || [[ "${CI:-false}" == "true" ]]; }; then
    die "CI and release DriverKit builds require OJD_USE_LOCAL_SWIFTERKIT=0"
  fi
}

_driverkit_versions() {
  DRIVERKIT_SHORT_VERSION="${OJD_BUNDLE_SHORT_VERSION:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}"
  python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" \
    --check-release "$DRIVERKIT_SHORT_VERSION" >/dev/null || exit 2
  # The DEXT shares the app's build number; install flows may pass a
  # development-stage DEXT_BUNDLE_VERSION so a rebuilt tree replaces it.
  DRIVERKIT_BUILD_VERSION="${DEXT_BUNDLE_VERSION:-${OJD_BUNDLE_VERSION:-}}"
  if [[ -z "$DRIVERKIT_BUILD_VERSION" ]]; then
    DRIVERKIT_BUILD_VERSION="$(python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" \
      "$PROJECT_DIR")" || exit 2
  fi
  python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" \
    --validate "$DRIVERKIT_BUILD_VERSION" >/dev/null || exit 2
}

generate_driverkit_project() {
  local output="${1:-$DRIVERKIT_GENERATED}"
  local generator_options=()
  [[ "$DRIVERKIT_INCLUDE_USB" == "1" ]] || generator_options+=(--without-usb-personality)
  _reject_local_swifterkit
  _driverkit_versions
  (
    cd "$PROJECT_DIR" || exit
    local swift_build=("$SWIFT_BUILD_BIN" --scratch-path "$DRIVERKIT_ROOT/swiftpm")
    "${swift_build[@]}" --product DriverKitGenerator
    local generator_bin
    generator_bin="$("${swift_build[@]}" --show-bin-path)/DriverKitGenerator"
    [[ -x "$generator_bin" ]] || die "DriverKitGenerator executable was not built"
    "$generator_bin" \
      --output "$output" \
      "${generator_options[@]}" \
      --short-version "$DRIVERKIT_SHORT_VERSION" \
      --build-version "$DRIVERKIT_BUILD_VERSION"
  )
}

_validate_driverkit_metadata() {
  local tree="$1" short_version="$2" build_version="$3"
  python3 - "$tree" "$short_version" "$build_version" "$DRIVERKIT_BUNDLE_ID" \
    "$DRIVERKIT_INCLUDE_USB" <<'PY'
import plistlib
import sys
from pathlib import Path

tree, short_version, build_version, bundle_id, include_usb = sys.argv[1:]
root = Path(tree)
info = plistlib.loads((root / "Info.plist").read_bytes())
entitlements = plistlib.loads((root / "SwifterKitRuntime.entitlements").read_bytes())
if bundle_id != "com.openjoystickdriver.VirtualHIDDevice":
    raise SystemExit("tooling bundle identity changed")
if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
    raise SystemExit("generated plist does not delegate bundle identity to Xcode")
if info.get("CFBundleShortVersionString") != short_version:
    raise SystemExit("generated short version mismatch")
if info.get("CFBundleVersion") != build_version:
    raise SystemExit("generated build version mismatch")
personalities = info.get("IOKitPersonalities", {})
expected_names = {"HIDFactory", "XboxUSB"} if include_usb == "1" else {"HIDFactory"}
if set(personalities) != expected_names:
    raise SystemExit(f"generated personalities mismatch: {sorted(personalities)}")
for name, personality in personalities.items():
    if personality.get("IOUserClass") != f"SwifterKit{name}RuntimeService":
        raise SystemExit(f"generated {name} runtime service class mismatch")
    if personality.get("IOUserServerName") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        raise SystemExit(f"generated {name} user-server identity mismatch")
factory = personalities["HIDFactory"]
if factory.get("IOProviderClass") != "IOUserResources":
    raise SystemExit("generated factory provider class mismatch")
if factory.get("IOResourceMatch") != "IOKit":
    raise SystemExit("generated factory resource match mismatch")
if factory.get("HIDDeviceProperties", {}).get("IOClass") != "AppleUserHIDDevice":
    raise SystemExit("generated factory device personality mismatch")
expected = {
    "com.apple.developer.driverkit": True,
    "com.apple.developer.driverkit.family.hid.device": True,
    "com.apple.developer.driverkit.transport.hid": True,
    "com.apple.developer.driverkit.family.hid.eventservice": True,
}
if include_usb == "1":
    expected["com.apple.developer.driverkit.transport.usb"] = [
        {"idVendor": 1118, "idProductArray": [721, 733, 739, 746, 2816, 2826, 2834]}
    ]
    usb = personalities["XboxUSB"]
    if usb.get("IOProviderClass") != "IOUSBHostInterface" or usb.get("idVendor") != 1118:
        raise SystemExit("generated USB personality provider or vendor mismatch")
    expected_interface = {
        "bConfigurationValue": 1,
        "bInterfaceNumber": 0,
        "bInterfaceClass": 255,
        "bInterfaceSubClass": 71,
        "bInterfaceProtocol": 208,
    }
    if any(usb.get(key) != value for key, value in expected_interface.items()):
        raise SystemExit("generated USB interface personality mismatch")
if entitlements != expected:
    raise SystemExit(f"generated DriverKit entitlements mismatch: {sorted(entitlements)}")
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
    "OSMinimumDriverKitVersion": "21.0",
}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f"built DriverKit metadata mismatch: {key}={info.get(key)!r}")
personalities = info.get("IOKitPersonalities", {})
if "HIDFactory" not in personalities:
    raise SystemExit("built DriverKit factory personality is missing")
for name, personality in personalities.items():
    if personality.get("IOUserClass") != f"SwifterKit{name}RuntimeService":
        raise SystemExit(f"built DriverKit {name} service class mismatch")
    if personality.get("IOUserServerName") != bundle_id:
        raise SystemExit(f"built DriverKit {name} user-server identity mismatch")
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

# Sets OJD_HOST_USERCLIENT to 1 when the GUI profile grants user-client access to the DEXT, or
# to 0 when a development profile has no grant for it (no key, or a list naming only other bundle
# IDs): Apple has not granted it yet, so the app is built without the DEXT and publishes through
# IOHIDUserDevice. Any other value, allow-any access, or a release profile without the grant is
# fatal.
_require_host_access_profile() {
  local profile="$1" decoded="$DRIVERKIT_ROOT/profile-entitlements.plist"
  mkdir -p "$DRIVERKIT_ROOT"
  decode_provisioning_profile "$profile" > "$decoded" \
    || die "Could not decode GUI provisioning profile for DriverKit allowlist validation"
  local state
  state="$(python3 - "$decoded" "$DRIVERKIT_BUNDLE_ID" "${OJD_ENV:-dev}" <<'PY'
import plistlib
import sys

profile, bundle_id, environment = sys.argv[1:]
entitlements = plistlib.loads(open(profile, "rb").read()).get("Entitlements", {})
if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("GUI provisioning profile grants forbidden allow-any DriverKit access")
value = entitlements.get("com.apple.developer.driverkit.userclient-access")
expected = [bundle_id]
ungranted = value is None or (
    isinstance(value, list)
    and all(isinstance(item, str) for item in value)
    and bundle_id not in value
)
if ungranted and environment != "release":
    print(0)
elif value == expected:
    print(1)
else:
    raise SystemExit(
        "GUI provisioning profile has an incorrect DriverKit user-client value: "
        f"expected {expected!r}, got {value!r}"
    )
PY
)" || exit 1
  OJD_HOST_USERCLIENT="$state"
}

_resolve_host_entitlements() {
  local profile="$1" output="$2"
  _require_host_access_profile "$profile"
  resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$output"
  if [[ "$OJD_HOST_USERCLIENT" != "1" ]]; then
    echo "Host profile lacks DriverKit user-client access; building without the DEXT (IOHIDUserDevice fallback)"
    python3 - "$output" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    entitlements = plistlib.load(handle)
entitlements.pop("com.apple.developer.driverkit.userclient-access", None)
with open(sys.argv[1], "wb") as handle:
    plistlib.dump(entitlements, handle)
PY
  fi
}

# Checks the dext profile and sets DRIVERKIT_INCLUDE_USB and DRIVERKIT_SIGNING_ENTITLEMENTS:
# a profile without Apple's USB transport grant builds the factory personality only.
_require_driverkit_profile() {
  local profile="$1" decoded="$DRIVERKIT_ROOT/dext-profile-entitlements.plist"
  mkdir -p "$DRIVERKIT_ROOT"
  decode_provisioning_profile "$profile" > "$decoded" \
    || die "Could not decode DriverKit provisioning profile"
  local usb
  usb="$(python3 - "$decoded" <<'PY'
import plistlib
import sys

entitlements = plistlib.loads(open(sys.argv[1], "rb").read()).get("Entitlements", {})
if entitlements.get("com.apple.developer.driverkit") is not True:
    raise SystemExit("DriverKit provisioning profile is missing the DriverKit base entitlement")
if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("DriverKit provisioning profile grants forbidden allow-any access")
for key in (
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
):
    if entitlements.get(key) is not True:
        raise SystemExit(f"VirtualHIDDevice profile is missing {key}")
if "com.apple.developer.hid.virtual.device" in entitlements:
    raise SystemExit("VirtualHIDDevice profile contains the app-only virtual HID entitlement")
production_usb = [
    {"idVendor": 1118, "idProduct": 721},
    {"idVendor": 1118, "idProduct": 746},
    {"idVendor": 1118, "idProduct": 2834},
    {"idVendor": 1118, "idProduct": 2816},
    {"idVendor": 1118, "idProduct": 739},
    {"idVendor": 1118, "idProduct": 2826},
    {"idVendor": 1118, "idProduct": 733},
]
actual_usb = entitlements.get("com.apple.developer.driverkit.transport.usb")
if actual_usb is None:
    print(0)
elif actual_usb == production_usb:
    print(1)
else:
    raise SystemExit(
        "DriverKit profile USB entitlement differs from Apple's exact seven-device grant: "
        f"{actual_usb!r}"
    )
PY
)" || exit 1
  DRIVERKIT_INCLUDE_USB="$usb"
  DRIVERKIT_SIGNING_ENTITLEMENTS="$DRIVERKIT_AUTHORED_ENTITLEMENTS"
  if [[ "$usb" != "1" ]]; then
    echo "DriverKit profile has no USB transport grant; building the HID factory personality only"
    DRIVERKIT_SIGNING_ENTITLEMENTS="$DRIVERKIT_ROOT/${DRIVERKIT_PRODUCT_NAME}-factory.entitlements"
    python3 - "$DRIVERKIT_AUTHORED_ENTITLEMENTS" "$DRIVERKIT_SIGNING_ENTITLEMENTS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    entitlements = plistlib.load(handle)
entitlements.pop("com.apple.developer.driverkit.transport.usb", None)
with open(sys.argv[2], "wb") as handle:
    plistlib.dump(entitlements, handle)
PY
  fi
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
  python3 - "$decoded" "$decoded_profile" "$OJD_HOST_USERCLIENT" <<'PY'
import plistlib
import sys

signed_path, profile_path, granted = sys.argv[1:]
signed = plistlib.loads(open(signed_path, "rb").read())
profile = plistlib.loads(open(profile_path, "rb").read()).get("Entitlements", {})
key = "com.apple.developer.driverkit.userclient-access"
if granted != "1":
    if key in signed:
        raise SystemExit(
            f"signed host has {key} but the profile does not grant the DEXT: "
            f"signed={signed.get(key)!r}"
        )
elif signed.get(key) != profile.get(key):
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
  python3 - "$decoded" "$DRIVERKIT_SIGNING_ENTITLEMENTS" <<'PY'
import plistlib
import sys

signed = plistlib.loads(open(sys.argv[1], "rb").read())
expected = plistlib.loads(open(sys.argv[2], "rb").read())
for key, value in expected.items():
    if signed.get(key) != value:
        raise SystemExit(f"signed DriverKit entitlement mismatch for {key}: {signed.get(key)!r}")
if signed.get("com.apple.developer.driverkit.allow-any-userclient-access"):
    raise SystemExit("signed dext grants forbidden allow-any DriverKit access")
if "com.apple.developer.driverkit.transport.usb" in signed and (
    "com.apple.developer.driverkit.transport.usb" not in expected
):
    raise SystemExit("signed factory-only dext contains USB transport")
if "com.apple.developer.hid.virtual.device" in signed:
    raise SystemExit("signed dext contains the app-only virtual HID entitlement")
PY
}

_driverkit_xcodebuild() {
  local configuration="$1"
  shift
  xcodebuild \
    -project "$DRIVERKIT_PROJECT" \
    -scheme "$DRIVERKIT_SCHEME" \
    -configuration "$configuration" \
    -destination "generic/platform=DriverKit" \
    -derivedDataPath "$DRIVERKIT_DERIVED_DATA" \
    PRODUCT_BUNDLE_IDENTIFIER="$DRIVERKIT_BUNDLE_ID" \
    PRODUCT_NAME="$DRIVERKIT_PRODUCT_NAME" \
    EXECUTABLE_NAME="$DRIVERKIT_PRODUCT_NAME" \
    DRIVERKIT_DEPLOYMENT_TARGET=21.0 \
    CLANG_CXX_LANGUAGE_STANDARD=gnu++20 \
    "$@" clean build
}

# Builds, signs, and embeds the dext into the app.
_build_dext() {
  local configuration="$1" app="$2"
  [[ -f "$DRIVERKIT_PROFILE" ]] \
    || die "DriverKit provisioning profile not found: $DRIVERKIT_PROFILE"
  _require_driverkit_profile "$DRIVERKIT_PROFILE"

  rm -rf "$DRIVERKIT_GENERATED" "$DRIVERKIT_DERIVED_DATA"
  generate_driverkit_project
  _validate_driverkit_metadata \
    "$DRIVERKIT_GENERATED" "$DRIVERKIT_SHORT_VERSION" "$DRIVERKIT_BUILD_VERSION"

  local identity="${DEXT_BUILD_IDENTITY:-$CODESIGN_IDENTITY}"
  verify_profile_cert "$DRIVERKIT_PROFILE" "$identity"
  local signing=(
    CODE_SIGN_IDENTITY="$identity"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    PROVISIONING_PROFILE_SPECIFIER="$DRIVERKIT_PROFILE_SPECIFIER"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_ENTITLEMENTS="$DRIVERKIT_SIGNING_ENTITLEMENTS"
  )
  if [[ "$OJD_ENV" == "release" ]]; then
    signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi
  _driverkit_xcodebuild "$configuration" "${signing[@]}"

  local product="$DRIVERKIT_DERIVED_DATA/Build/Products/${configuration}-driverkit/${DRIVERKIT_PRODUCT_NAME}.dext"
  [[ -d "$product" ]] || die "generated DriverKit product not found: $product"
  _validate_driverkit_product "$product"
  local extensions="$app/Contents/Library/SystemExtensions"
  local embedded="$extensions/${DRIVERKIT_BUNDLE_ID}.dext"
  # Any other extension left by an earlier build would ship unvalidated.
  rm -rf "$extensions"
  mkdir -p "$extensions"
  cp -R "$product" "$embedded"
  cp "$DRIVERKIT_PROFILE" "$embedded/embedded.provisionprofile"

  local sign_args=(--force --sign "$identity" --generate-entitlement-der --entitlements "$DRIVERKIT_SIGNING_ENTITLEMENTS")
  [[ "$OJD_ENV" == "release" ]] && sign_args+=(--options runtime --timestamp)
  codesign "${sign_args[@]}" "$embedded"
  _require_signed_driverkit_entitlements "$embedded"
  echo "DriverKit extension built and embedded: $embedded"
}

build_dext_bundle() {
  [[ "${CODESIGN_IDENTITY:--}" != "-" ]] \
    || die "DriverKit extensions cannot use ad-hoc signing; run ./Scripts/ojd signing configure"
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] \
    || die "DEVELOPMENT_TEAM not set; run ./Scripts/ojd signing configure"
  local configuration="Debug"
  [[ "$OJD_ENV" == "release" ]] && configuration="Release"
  local app="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  [[ -d "$app" ]] || die "app bundle not found; run ./Scripts/ojd build dev first"

  _require_host_access_profile "$GUI_PROFILE"
  if [[ "$OJD_HOST_USERCLIENT" == "1" ]]; then
    _build_dext "$configuration" "$app"
  else
    echo "Skipping the DriverKit extension: the host profile cannot open its user client"
    rm -rf "$app/Contents/Library/SystemExtensions"
  fi

  _resolve_host_entitlements "$GUI_PROFILE" "$GUI_ENTITLEMENTS"
  OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign "$app" --entitlements "$GUI_ENTITLEMENTS"
  _require_signed_host_access "$app" "$GUI_PROFILE"
}

# Generates the dext twice, checks that the outputs match and the metadata, and leaves the
# first generation in "$DRIVERKIT_ROOT/validation-one-<variant>".
_validate_driverkit_generation() {
  local variant="$1"
  local first="$DRIVERKIT_ROOT/validation-one-$variant"
  local second="$DRIVERKIT_ROOT/validation-two-$variant"
  rm -rf "$first" "$second" "$DRIVERKIT_DERIVED_DATA"
  generate_driverkit_project "$first"
  generate_driverkit_project "$second"
  diff -qr "$first" "$second" >/dev/null \
    || die "two fresh SwifterKit generations of the $variant extension are not byte-for-byte identical"
  rm -rf "$second"
  _validate_driverkit_metadata \
    "$first" "$DRIVERKIT_SHORT_VERSION" "$DRIVERKIT_BUILD_VERSION"
  if generate_driverkit_project "$first" >/dev/null 2>&1; then
    die "generator overwrote an existing destination"
  fi
}

# Builds the generated project unsigned for both architectures; needs no Apple grant.
_validate_driverkit_unsigned_build() {
  DRIVERKIT_GENERATED="$DRIVERKIT_ROOT/validation-one-$1"
  DRIVERKIT_PROJECT="$DRIVERKIT_GENERATED/SwifterKitRuntime.xcodeproj"
  _driverkit_xcodebuild Debug \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
  local product="$DRIVERKIT_DERIVED_DATA/Build/Products/Debug-driverkit/${DRIVERKIT_PRODUCT_NAME}.dext"
  _validate_driverkit_product "$product"
  local architectures
  architectures="$(lipo -archs "$product/$DRIVERKIT_PRODUCT_NAME")"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] \
    || die "installed DriverKit SDK did not produce arm64 and x86_64 slices for $1: $architectures"
}

validate_driverkit() {
  _driverkit_versions
  DRIVERKIT_INCLUDE_USB=1
  _validate_driverkit_generation full
  DRIVERKIT_INCLUDE_USB=0
  _validate_driverkit_generation factory
  DRIVERKIT_INCLUDE_USB=1
  # The generator writes USB matching as idProductArray, while Apple's grant lists each pair.
  python3 - "$DRIVERKIT_AUTHORED_ENTITLEMENTS" \
    "$DRIVERKIT_ROOT/validation-one-factory/SwifterKitRuntime.entitlements" <<'PY'
import plistlib
import sys

authored, generated = (plistlib.loads(open(path, "rb").read()) for path in sys.argv[1:])
key = "com.apple.developer.driverkit.transport.usb"
expected_usb = [
    {"idVendor": 1118, "idProduct": 721},
    {"idVendor": 1118, "idProduct": 746},
    {"idVendor": 1118, "idProduct": 2834},
    {"idVendor": 1118, "idProduct": 2816},
    {"idVendor": 1118, "idProduct": 739},
    {"idVendor": 1118, "idProduct": 2826},
    {"idVendor": 1118, "idProduct": 733},
]
if authored.pop(key, None) != expected_usb:
    raise SystemExit("authored USB entitlement differs from Apple's exact seven-device grant")
if authored != generated:
    raise SystemExit(
        "authored VirtualHIDDevice entitlements differ from the SwifterKit-generated set: "
        f"authored={authored!r}, generated={generated!r}"
    )
PY

  local tracked_native
  tracked_native="$(
    git ls-files | { grep -E '^(DriverKitExtension/|\.build/driverkit/|.*\.(iig|cpp|hpp)$)' || [[ $? -eq 1 ]]; } \
      | while IFS= read -r path; do
          [[ ! -e "$PROJECT_DIR/$path" ]] || printf '%s\n' "$path"
        done
  )"
  if [[ -n "$tracked_native" ]]; then
    die "tracked manual or generated DriverKit artifacts remain"
  fi
  _validate_host_entitlement_source
  local package_dump="$DRIVERKIT_ROOT/package.json"
  "$SWIFT_PACKAGE_BIN" --package-path "$PROJECT_DIR" dump-package > "$package_dump"
  local swifterkit_source=pinned
  _swifterkit_is_local && swifterkit_source=local
  python3 - "$package_dump" "$swifterkit_source" <<'PY'
import json
import sys

package = json.load(open(sys.argv[1]))
dependencies = package["dependencies"]
local_swifterkit = sys.argv[2] == "local"
if local_swifterkit:
    local = [
        dependency["fileSystem"][0]
        for dependency in dependencies
        if "fileSystem" in dependency
    ]
    if [value.get("identity") for value in local] != ["swifterkit"]:
        raise SystemExit(f"expected only the local SwifterKit path dependency: {local!r}")
expected_dependencies = [] if local_swifterkit else [
    {
        "identity": "swifterkit",
        "location": "https://github.com/xsyetopz/SwifterKit.git",
        "requirement": {"range": [{"lowerBound": "0.3.0", "upperBound": "1.0.0"}]},
    },
]
expected_dependencies += [
    {
        "identity": "swift-argument-parser",
        "location": "https://github.com/apple/swift-argument-parser.git",
        "requirement": {"exact": ["1.8.2"]},
    },
]
actual_dependencies = []
for dependency in dependencies:
    source = dependency.get("sourceControl", [])
    if not source:
        continue
    value = source[0]
    remote = value.get("location", {}).get("remote", [{}])[0]
    actual_dependencies.append(
        {
            "identity": value.get("identity"),
            "location": remote.get("urlString"),
            "requirement": value.get("requirement"),
        }
    )
if actual_dependencies != expected_dependencies:
    raise SystemExit(f"SwiftPM dependency contract mismatch: {actual_dependencies!r}")

targets = {target["name"]: target for target in package["targets"]}
required_targets = {"OpenJoystickDriverKit", "OpenJoystickDriverUSB", "DriverKitGenerator"}
if not required_targets <= targets.keys():
    raise SystemExit(f"SwiftPM DriverKit targets are missing: {sorted(required_targets - targets.keys())}")

def products(target):
    return {
        dependency["product"][0]
        for dependency in target.get("dependencies", [])
        if "product" in dependency
    }

if products(targets["OpenJoystickDriverKit"]):
    raise SystemExit("OpenJoystickDriverKit unexpectedly has a package product dependency")
for name in ("OpenJoystickDriverUSB", "DriverKitGenerator"):
    if products(targets[name]) != {"SwifterKit"}:
        raise SystemExit(f"{name} does not declare exactly the SwifterKit product dependency")
PY

  _validate_driverkit_unsigned_build full
  echo "DriverKit generation, architecture, and unsigned universal build validation passed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    generate)
      shift
      if [[ "${1:-}" == "--without-usb-personality" ]]; then
        DRIVERKIT_INCLUDE_USB=0
        shift
      fi
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
    *) die "expected generate [--without-usb-personality] [output] or validate" ;;
  esac
fi
