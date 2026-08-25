# shellcheck shell=bash
# Application bundle builder for scripts/build-tools/build.sh.

build_app_bundle() {
  _require_codesign_identity

  for profile_var in GUI_PROFILE; do
    profile_path="${!profile_var}"
    if [[ ! -f "$profile_path" ]]; then
      echo "ERROR: Provisioning profile not found: $profile_path"
      echo "Fix: run: ./scripts/ojd signing install-profiles"
      exit 1
    fi
  done

  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM not set."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi

  _require_profile_entitlement_value \
    "$GUI_PROFILE" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver" \
    "GUI app signing identity / provisioning profile" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement_value \
    "$GUI_PROFILE" \
    "com.apple.developer.team-identifier" \
    "$DEVELOPMENT_TEAM" \
    "GUI app signing identity / provisioning profile" \
    "Fix: run ./scripts/ojd signing configure, then reinstall matching GUI profiles."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.system-extension.install" \
    "GUI app (system extension install)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with the System Extension install capability, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "GUI app (virtual HID backend)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with entitlement com.apple.developer.hid.virtual.device, then reinstall profiles (./scripts/ojd signing install-profiles)."

  if [[ "$OJD_ENV" == "release" ]]; then
    echo "Building release binaries (universal)..."
    cd "$PROJECT_DIR" || exit
    "$SWIFT_BIN" build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    local gui_bin="$GUI_RELEASE"
  else
    echo "Building debug binaries (universal)..."
    cd "$PROJECT_DIR" || exit
    "$SWIFT_BIN" build --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    local gui_bin="$PROJECT_DIR/.build/apple/Products/Debug/OpenJoystickDriver"
  fi

  mkdir -p "$PROJECT_DIR/.build"
  if [[ -L "$PROJECT_DIR/.build/debug" && ! -e "$PROJECT_DIR/.build/debug" ]]; then
    _DEBUG_TARGET="$(readlink "$PROJECT_DIR/.build/debug")"
    mkdir -p "$PROJECT_DIR/.build/$_DEBUG_TARGET"
    unset _DEBUG_TARGET
  fi
  _resolve_host_entitlements "$GUI_PROFILE" "$GUI_ENTITLEMENTS"

  local GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  local GUI_CONTENTS="$GUI_APP/Contents"
  local GUI_MACOS="$GUI_CONTENTS/MacOS"
  local bundle_short_version="${OJD_BUNDLE_SHORT_VERSION:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}"
  local bundle_version="${OJD_BUNDLE_VERSION:-1}"

  echo "Creating app bundle..."
  rm -rf "$GUI_APP"
  mkdir -p "$GUI_MACOS"
  cp "$gui_bin" "$GUI_MACOS/OpenJoystickDriver"

  local BUILD_DIR
  BUILD_DIR="$(dirname "$gui_bin")"
  local GUI_RESOURCES="$GUI_CONTENTS/Resources"
  mkdir -p "$GUI_RESOURCES"
  cp "$PROJECT_DIR/Sources/OpenJoystickDriver/Resources/OpenJoystickDriver.icns" \
    "$GUI_RESOURCES/OpenJoystickDriver.icns"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$GUI_RESOURCES/"
  done
  # SwiftUI's literal-based controls resolve Localizable.strings from the
  # process main bundle. Keep the Kit bundle as the single source of truth,
  # then mirror only its locale directories into the app bundle so AppKit,
  # SwiftUI, and accessibility text share the same translations.
  local kit_bundle="$GUI_RESOURCES/OpenJoystickDriver_OpenJoystickDriverKit.bundle"
  if [[ -d "$kit_bundle/Contents/Resources" ]]; then
    for localization in "$kit_bundle/Contents/Resources"/*.lproj; do
      [[ -d "$localization" ]] && cp -R "$localization" "$GUI_RESOURCES/"
    done
  fi
  cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$GUI_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

  cp "$OJD_APP_INFO_PLIST" "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$bundle_short_version" \
    "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$bundle_version" "$GUI_CONTENTS/Info.plist"

  echo "Signing GUI using:    $GUI_IDENTITY"
  for bundle in "$GUI_RESOURCES"/*.bundle; do
    [[ -d "$bundle" ]] && OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign_resource_bundle "$bundle"
  done
  OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign "$GUI_APP" --entitlements "$GUI_ENTITLEMENTS"

  _require_signed_entitlement_value \
    "$GUI_APP" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver" \
    "GUI app signed entitlements" \
    "Fix: regenerate GUI entitlements/provisioning, then rebuild."
  _require_signed_entitlement_value \
    "$GUI_APP" \
    "com.apple.developer.hid.virtual.device" \
    "true" \
    "GUI app Compatibility backend" \
    "Fix: enable com.apple.developer.hid.virtual.device on the GUI profile, then rebuild."
  _require_signed_host_access "$GUI_APP" "$GUI_PROFILE"
  if [[ "$OJD_ENV" == "release" ]]; then
    verify_profile_cert "$GUI_PROFILE" "$GUI_IDENTITY"
  fi

  echo ""
  echo "Signed GUI with:    $GUI_IDENTITY"
  echo "  GUI app:        $GUI_APP"
}
