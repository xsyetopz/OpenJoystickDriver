# shellcheck shell=bash
# App and DriverKit bundle builders for scripts/ojd-build.sh.

build_app_bundle() {
  _require_codesign_identity

  for profile_var in DAEMON_PROFILE GUI_PROFILE; do
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

  _require_profile_entitlement_value \
    "$DAEMON_PROFILE" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver.daemon" \
    "Daemon app signing identity / provisioning profile" \
    "Fix: regenerate the daemon provisioning profile for Identifier com.openjoystickdriver.daemon, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement_value \
    "$DAEMON_PROFILE" \
    "com.apple.developer.team-identifier" \
    "$DEVELOPMENT_TEAM" \
    "Daemon app signing identity / provisioning profile" \
    "Fix: run ./scripts/ojd signing configure, then reinstall matching daemon profiles."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.system-extension.install" \
    "GUI app (system extension install)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with the System Extension install capability, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "GUI app (Compatibility / embedded backend IOHIDUserDevice)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with entitlement com.apple.developer.hid.virtual.device, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$DAEMON_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "Daemon (Compatibility IOHIDUserDevice)" \
    "Fix: enable entitlement com.apple.developer.hid.virtual.device on Identifier com.openjoystickdriver.daemon, regenerate the daemon provisioning profile, then reinstall profiles (./scripts/ojd signing install-profiles)."

  if [[ "$OJD_ENV" == "release" ]]; then
    setup_libusb_pkgconfig
    echo "Building release binaries (universal)..."
    cd "$PROJECT_DIR"
    "$SWIFT_BIN" build -c release --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    "$SWIFT_BIN" build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    local daemon_bin="$DAEMON_RELEASE"
    local gui_bin="$GUI_RELEASE"
  else
    setup_libusb_pkgconfig
    echo "Building debug binaries (universal)..."
    cd "$PROJECT_DIR"
    "$SWIFT_BIN" build --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    "$SWIFT_BIN" build --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    local daemon_bin="$PROJECT_DIR/.build/apple/Products/Debug/OpenJoystickDriverDaemon"
    local gui_bin="$PROJECT_DIR/.build/apple/Products/Debug/OpenJoystickDriver"
  fi

  mkdir -p "$PROJECT_DIR/.build"
  if [[ -L "$PROJECT_DIR/.build/debug" && ! -e "$PROJECT_DIR/.build/debug" ]]; then
    _DEBUG_TARGET="$(readlink "$PROJECT_DIR/.build/debug")"
    mkdir -p "$PROJECT_DIR/.build/$_DEBUG_TARGET"
    unset _DEBUG_TARGET
  fi
  resolve_entitlements "$DAEMON_ENTITLEMENTS_TEMPLATE" "$DAEMON_ENTITLEMENTS"
  resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"

  local GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  local GUI_CONTENTS="$GUI_APP/Contents"
  local GUI_MACOS="$GUI_CONTENTS/MacOS"
  local GUI_LOGIN_ITEMS="$GUI_CONTENTS/Library/LoginItems"
  local GUI_FRAMEWORKS="$GUI_CONTENTS/Frameworks"
  local bundle_short_version="${OJD_BUNDLE_SHORT_VERSION:-0.5.0-alpha.5}"
  local bundle_version="${OJD_BUNDLE_VERSION:-1}"
  local sparkle_feed_url="${SPARKLE_FEED_URL:-https://github.com/xsyetopz/OpenJoystickDriver/releases/latest/download/appcast.xml}"
  local sparkle_public_ed_key="${SPARKLE_PUBLIC_ED_KEY:-}"

  if [[ "$OJD_ENV" == "release" && -z "$sparkle_public_ed_key" ]]; then
    echo "ERROR: SPARKLE_PUBLIC_ED_KEY not set."
    echo "Fix: add the Sparkle EdDSA public key to CI/local release env."
    exit 1
  fi

  echo "Creating app bundle..."
  rm -rf "$GUI_APP"
  mkdir -p "$GUI_MACOS" "$GUI_LOGIN_ITEMS" "$GUI_FRAMEWORKS"
  cp "$gui_bin" "$GUI_MACOS/OpenJoystickDriver"

  local BUILD_DIR
  BUILD_DIR="$(dirname "$daemon_bin")"
  local GUI_RESOURCES="$GUI_CONTENTS/Resources"
  mkdir -p "$GUI_RESOURCES"
  cp "$PROJECT_DIR/Sources/OpenJoystickDriver/Resources/OpenJoystickDriver.icns" \
    "$GUI_RESOURCES/OpenJoystickDriver.icns"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$GUI_RESOURCES/"
  done
  for framework in "$BUILD_DIR"/*.framework; do
    [[ -d "$framework" ]] && cp -R "$framework" "$GUI_FRAMEWORKS/"
  done

  local LAUNCHAGENTS_SRC="$PROJECT_DIR/Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
  local LAUNCHAGENTS_DST="$GUI_CONTENTS/Library/LaunchAgents"
  mkdir -p "$LAUNCHAGENTS_DST"
  cp "$LAUNCHAGENTS_SRC" "$LAUNCHAGENTS_DST/com.openjoystickdriver.daemon.plist"

  cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$GUI_CONTENTS/embedded.provisionprofile" 2> /dev/null || true

  cat > "$GUI_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleDisplayName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleIconFile</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.5.0-alpha.5</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>OpenJoystickDriver needs Input Monitoring to read controller input and publish virtual gamepad events.</string>
    <key>NSSystemExtensionUsageDescription</key>
    <string>OpenJoystickDriver uses this extension to present physical controllers as a standard virtual HID gamepad to games and applications, without requiring Accessibility permission.</string>
</dict>
</plist>
PLIST
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$bundle_short_version" \
    "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$bundle_version" "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace SUFeedURL -string "$sparkle_feed_url" "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace SUEnableAutomaticChecks -bool YES "$GUI_CONTENTS/Info.plist"
  /usr/bin/plutil -replace SUAutomaticallyUpdate -bool NO "$GUI_CONTENTS/Info.plist"
  if [[ -n "$sparkle_public_ed_key" ]]; then
    /usr/bin/plutil -replace SUPublicEDKey -string "$sparkle_public_ed_key" \
      "$GUI_CONTENTS/Info.plist"
  fi

  local DAEMON_BUNDLE="$GUI_LOGIN_ITEMS/OpenJoystickDriverDaemon.app"
  local DAEMON_BUNDLE_CONTENTS="$DAEMON_BUNDLE/Contents"
  local DAEMON_BUNDLE_MACOS="$DAEMON_BUNDLE_CONTENTS/MacOS"

  echo "Creating daemon bundle..."
  mkdir -p "$DAEMON_BUNDLE_MACOS"
  cp "$daemon_bin" "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
  cp "$DAEMON_PROFILE" "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile" 2> /dev/null || true

  local DAEMON_RESOURCES="$DAEMON_BUNDLE_CONTENTS/Resources"
  mkdir -p "$DAEMON_RESOURCES"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$DAEMON_RESOURCES/"
  done

  cat > "$DAEMON_BUNDLE_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver.daemon</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundleDisplayName</key>
    <string>OpenJoystickDriver Daemon</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.5.0-alpha.5</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>OpenJoystickDriver Daemon needs Input Monitoring to read controller input and publish virtual gamepad events.</string>
</dict>
</plist>
PLIST
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$bundle_short_version" \
    "$DAEMON_BUNDLE_CONTENTS/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$bundle_version" \
    "$DAEMON_BUNDLE_CONTENTS/Info.plist"

  echo "Signing GUI using:    $GUI_IDENTITY"
  echo "Signing daemon using: $DAEMON_IDENTITY"
  for bundle in "$GUI_RESOURCES"/*.bundle; do
    [[ -d "$bundle" ]] && OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign_resource_bundle "$bundle"
  done
  for framework in "$GUI_FRAMEWORKS"/*.framework; do
    if [[ -d "$framework" && "$(basename "$framework")" == "Sparkle.framework" ]]; then
      local sparkle_extra_args=()
      if [[ "$OJD_ENV" == "release" ]]; then
        sparkle_extra_args=(--options runtime --timestamp)
      fi
      /usr/bin/codesign --force --sign "$GUI_IDENTITY" \
        "${sparkle_extra_args[@]}" \
        "$framework/Versions/B/XPCServices/Installer.xpc"
      /usr/bin/codesign --force --sign "$GUI_IDENTITY" \
        "${sparkle_extra_args[@]}" \
        --preserve-metadata=entitlements \
        "$framework/Versions/B/XPCServices/Downloader.xpc"
      /usr/bin/codesign --force --sign "$GUI_IDENTITY" \
        "${sparkle_extra_args[@]}" \
        "$framework/Versions/B/Autoupdate"
      /usr/bin/codesign --force --sign "$GUI_IDENTITY" \
        "${sparkle_extra_args[@]}" \
        "$framework/Versions/B/Updater.app"
      /usr/bin/codesign --force --sign "$GUI_IDENTITY" \
        "${sparkle_extra_args[@]}" \
        "$framework"
    fi
  done
  for bundle in "$DAEMON_RESOURCES"/*.bundle; do
    [[ -d "$bundle" ]] && OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign_resource_bundle "$bundle"
  done
  OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"
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
  _require_signed_entitlement_value \
    "$DAEMON_BUNDLE" \
    "com.apple.application-identifier" \
    "${DEVELOPMENT_TEAM}.com.openjoystickdriver.daemon" \
    "Daemon app signed entitlements" \
    "Fix: regenerate daemon entitlements/provisioning, then rebuild."
  _require_signed_entitlement_value \
    "$DAEMON_BUNDLE" \
    "com.apple.developer.hid.virtual.device" \
    "true" \
    "Daemon Compatibility backend" \
    "Fix: enable com.apple.developer.hid.virtual.device on the daemon profile, then rebuild."

  if [[ "$OJD_ENV" == "release" ]]; then
    verify_profile_cert "$GUI_PROFILE" "$GUI_IDENTITY"
    verify_profile_cert "$DAEMON_PROFILE" "$DAEMON_IDENTITY"
  fi

  echo ""
  echo "Signed GUI with:    $GUI_IDENTITY"
  echo "Signed daemon with: $DAEMON_IDENTITY"
  echo "  GUI app:        $GUI_APP"
  echo "  Daemon app:     $DAEMON_BUNDLE"
}

source "$SCRIPT_DIR/ojd-build-dext.sh"
