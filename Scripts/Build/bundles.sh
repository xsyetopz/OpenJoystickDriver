# shellcheck shell=bash
# Application bundle builder for Scripts/Build/build.sh.

build_app_bundle() {
  _require_codesign_identity

  if [[ ! -f "$GUI_PROFILE" ]]; then
    echo "ERROR: Provisioning profile not found: $GUI_PROFILE"
    echo "Fix: run: ./Scripts/ojd signing install-profiles"
    exit 1
  fi

  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM not set."
    echo "Fix: run: ./Scripts/ojd signing configure"
    exit 1
  fi

  _require_profile_entitlement_value \
    "$GUI_PROFILE" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver" \
    "GUI app signing identity / provisioning profile" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver, then reinstall profiles (./Scripts/ojd signing install-profiles)."

  _require_profile_entitlement_value \
    "$GUI_PROFILE" \
    "com.apple.developer.team-identifier" \
    "$DEVELOPMENT_TEAM" \
    "GUI app signing identity / provisioning profile" \
    "Fix: run ./Scripts/ojd signing configure, then reinstall matching GUI profiles."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.system-extension.install" \
    "GUI app (system extension install)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with the System Extension install capability, then reinstall profiles (./Scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "GUI app (virtual HID backend)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with entitlement com.apple.developer.hid.virtual.device, then reinstall profiles (./Scripts/ojd signing install-profiles)."

  local configuration=Debug
  local actions=(build)
  if [[ "$OJD_ENV" == "release" ]]; then
    configuration=Release
    actions=(clean build)
  fi
  echo "Building $configuration app (universal)..."
  # Xcode extracts the App Intents metadata that Shortcuts reads, which `swift build` cannot.
  # TOOLCHAINS is unset because the package must build with the selected Xcode's own toolchain.
  env -u TOOLCHAINS xcodebuild \
    -project "$GUI_PROJECT" \
    -scheme "$GUI_SCHEME" \
    -configuration "$configuration" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$GUI_DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_DEBUG_DYLIB=NO \
    CODE_SIGNING_ALLOWED=NO \
    "${actions[@]}"
  local built_app="$GUI_DERIVED_DATA/Build/Products/$configuration/OpenJoystickDriver.app"
  if [[ ! -d "$built_app/Contents/Resources/Metadata.appintents" ]]; then
    echo "ERROR: $built_app has no Contents/Resources/Metadata.appintents."
    echo "Fix: build the app target of $GUI_PROJECT, which runs the App Intents metadata extraction."
    exit 1
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
  local bundle_short_version="${OJD_BUNDLE_SHORT_VERSION:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}"
  local bundle_version="${OJD_BUNDLE_VERSION:-}"
  if [[ -z "$bundle_version" ]]; then
    bundle_version="$(python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" "$PROJECT_DIR")"
  fi
  local source_commit="${OJD_SOURCE_COMMIT:-}"
  if [[ -z "$source_commit" ]]; then
    source_commit="$(git -C "$PROJECT_DIR" rev-parse --verify HEAD)"
  fi
  local source_state="${OJD_SOURCE_STATE:-}"
  if [[ -z "$source_state" ]]; then
    if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=all)" ]]; then
      source_state="dirty"
    else
      source_state="clean"
    fi
  fi
  if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: OJD source commit must be a full 40-character lowercase Git SHA."
    exit 1
  fi
  if [[ "$source_state" != "clean" && "$source_state" != "dirty" ]]; then
    echo "ERROR: OJD source state must be clean or dirty."
    exit 1
  fi

  echo "Creating app bundle..."
  rm -rf "$GUI_APP"
  ditto "$built_app" "$GUI_APP"

  local GUI_RESOURCES="$GUI_CONTENTS/Resources"
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

  /usr/bin/plutil -replace CFBundleShortVersionString -string "$bundle_short_version" \
    "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$bundle_version" "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace OJDSourceCommit -string "$source_commit" "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace OJDSourceState -string "$source_state" "$GUI_CONTENTS/Info.plist"

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
    "GUI app virtual HID output" \
    "Fix: enable com.apple.developer.hid.virtual.device on the GUI profile, then rebuild."
  _require_signed_host_access "$GUI_APP" "$GUI_PROFILE"
  if [[ "$OJD_ENV" == "release" ]]; then
    verify_profile_cert "$GUI_PROFILE" "$GUI_IDENTITY"
  fi

  echo ""
  echo "Signed GUI with:    $GUI_IDENTITY"
  echo "  GUI app:        $GUI_APP"
}
