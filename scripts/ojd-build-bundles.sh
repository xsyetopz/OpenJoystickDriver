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
    swift build -c release --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    swift build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    local daemon_bin="$DAEMON_RELEASE"
    local gui_bin="$GUI_RELEASE"
  else
    setup_libusb_pkgconfig
    echo "Building debug binaries (universal)..."
    cd "$PROJECT_DIR"
    swift build --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    swift build --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
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

  echo "Creating app bundle..."
  rm -rf "$GUI_APP"
  mkdir -p "$GUI_MACOS"
  cp "$gui_bin" "$GUI_MACOS/OpenJoystickDriver"
  cp "$daemon_bin" "$GUI_MACOS/OpenJoystickDriverDaemon"

  local BUILD_DIR
  BUILD_DIR="$(dirname "$daemon_bin")"
  local GUI_RESOURCES="$GUI_CONTENTS/Resources"
  mkdir -p "$GUI_RESOURCES"
  cp "$PROJECT_DIR/Sources/OpenJoystickDriver/Resources/OpenJoystickDriver.icns" \
    "$GUI_RESOURCES/OpenJoystickDriver.icns"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$GUI_RESOURCES/"
  done

  local LAUNCHAGENTS_SRC="$PROJECT_DIR/Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
  local LAUNCHAGENTS_DST="$GUI_CONTENTS/Library/LaunchAgents"
  mkdir -p "$LAUNCHAGENTS_DST"
  cp "$LAUNCHAGENTS_SRC" "$LAUNCHAGENTS_DST/com.openjoystickdriver.daemon.plist"

  cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$GUI_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

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
    <string>0.5.0-alpha.3</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSystemExtensionUsageDescription</key>
    <string>OpenJoystickDriver uses this extension to present physical controllers as a standard virtual HID gamepad to games and applications, without requiring Accessibility permission.</string>
</dict>
</plist>
PLIST

  local DAEMON_BUNDLE="$GUI_MACOS/OpenJoystickDriverDaemon.app"
  local DAEMON_BUNDLE_CONTENTS="$DAEMON_BUNDLE/Contents"
  local DAEMON_BUNDLE_MACOS="$DAEMON_BUNDLE_CONTENTS/MacOS"

  echo "Creating daemon bundle..."
  mkdir -p "$DAEMON_BUNDLE_MACOS"
  cp "$daemon_bin" "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
  cp "$DAEMON_PROFILE" "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

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
    <string>OpenJoystickDriver Helper</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.5.0-alpha.3</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

  echo "Signing GUI using:    $GUI_IDENTITY"
  echo "Signing daemon using: $DAEMON_IDENTITY"
  for bundle in "$GUI_RESOURCES"/*.bundle; do
    [[ -d "$bundle" ]] && OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign_resource_bundle "$bundle"
  done
  for bundle in "$DAEMON_RESOURCES"/*.bundle; do
    [[ -d "$bundle" ]] && OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign_resource_bundle "$bundle"
  done
  OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"
  OJD_ACTIVE_SIGN_IDENTITY="$DAEMON_IDENTITY" ojd_sign "$GUI_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign "$GUI_APP" --entitlements "$GUI_ENTITLEMENTS"

  if [[ "$OJD_ENV" == "release" ]]; then
    verify_profile_cert "$GUI_PROFILE" "$GUI_IDENTITY"
    verify_profile_cert "$DAEMON_PROFILE" "$DAEMON_IDENTITY"
  fi

  echo ""
  echo "Signed GUI with:    $GUI_IDENTITY"
  echo "Signed daemon with: $DAEMON_IDENTITY"
  echo "  GUI app:        $GUI_APP"
  echo "  Daemon bundle:  $DAEMON_BUNDLE"
}

# ---------------------------------------------------------------------------
# Build dext (from scripts/build-dext.sh)
# ---------------------------------------------------------------------------
build_dext_bundle() {
  if [[ "${CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "ERROR: DriverKit extensions cannot use ad-hoc signing."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM not set."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi

  local DEXT_DIR="$PROJECT_DIR/DriverKitExtension"
  local DEXT_PROJECT="$DEXT_DIR/OpenJoystickVirtualHID.xcodeproj"
  local DEXT_SCHEME="OpenJoystickVirtualHID"
  local DEXT_BUILD_DIR="$PROJECT_DIR/.build/dext"
  local DEXT_CONFIG
  if [[ "$OJD_ENV" == "release" ]]; then
    DEXT_CONFIG="Release"
  else
    DEXT_CONFIG="Debug"
  fi
  local DEXT_PRODUCT="$DEXT_BUILD_DIR/Build/Products/${DEXT_CONFIG}-driverkit/OpenJoystickVirtualHID.dext"
  local DEXT_BUNDLE_VERSION="${DEXT_BUNDLE_VERSION:-}"

  local DEXT_BUILD_IDENTITY="${DEXT_BUILD_IDENTITY:-$CODESIGN_IDENTITY}"
  local DEXT_BUILD_PROFILE="${DEXT_BUILD_PROFILE:-OpenJoystickDriver (VirtualHIDDevice)}"

  resolve_xcodebuild_identity() {
    local id="$1"
    if [[ "$id" =~ ^[0-9A-Fa-f]{40}$ ]]; then
      echo "$id"
      return 0
    fi
    if [[ "$id" == Apple\ Development:* ]]; then
      echo "Apple Development"
      return 0
    fi
    echo "$id"
  }

  local DEXT_BUILD_IDENTITY_XCODE
  DEXT_BUILD_IDENTITY_XCODE="$(resolve_xcodebuild_identity "$DEXT_BUILD_IDENTITY")"

  echo "Building DriverKit extension..."
  echo "  Build identity: $DEXT_BUILD_IDENTITY_XCODE"
  echo "  Build profile:  $DEXT_BUILD_PROFILE"
  echo "  Team: $DEVELOPMENT_TEAM"

  local DEXT_PROFILE_PATH="${DEXT_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
  if [[ -f "$DEXT_PROFILE_PATH" ]]; then
    read -r PROFILE_EMBEDDED_SHA1 PROFILE_TEAM CERT_OU < <(
      python3 - "$DEXT_PROFILE_PATH" <<'PY' 2>/dev/null || true
import plistlib, subprocess, sys, tempfile, os
profile = sys.argv[1]
def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if (p.returncode == 0 and p.stdout) else b""
raw = decode(profile)
if not raw or b"<?xml" not in raw:
    raise SystemExit(0)
raw = raw[raw.index(b"<?xml") :]
obj = plistlib.loads(raw)
team = ""
ti = obj.get("TeamIdentifier") or []
if isinstance(ti, list) and ti:
    team = str(ti[0])
certs = obj.get("DeveloperCertificates") or []
sha = ""
ou = ""
if certs:
    der = certs[0]
    fp = subprocess.run(["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"],
        input=der, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
    if "=" in fp:
        sha = fp.split("=",1)[1].replace(":","").lower()
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der); tmp=f.name
    try:
        subj = subprocess.run(["openssl","x509","-inform","DER","-in",tmp,"-noout","-subject","-nameopt","RFC2253"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
        if "OU=" in subj:
            ou = subj.split("OU=",1)[1].split(",",1)[0]
    finally:
        try: os.unlink(tmp)
        except OSError: pass
print(sha, team, ou)
PY
    ) || true

    local KEYCHAIN_SHA1S
    KEYCHAIN_SHA1S="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\"Apple Development:/{print tolower($2)}' | tr '\n' ' ')"
    if [[ -n "${PROFILE_EMBEDDED_SHA1:-}" && -n "${KEYCHAIN_SHA1S// /}" ]]; then
      if ! echo " $KEYCHAIN_SHA1S " | grep -q " ${PROFILE_EMBEDDED_SHA1} "; then
        echo ""
        echo "ERROR: DEXT provisioning profile does not match your Keychain Apple Development certificate."
        echo "Fix: regenerate the DEXT profile selecting the Apple Development cert you have locally, then run:"
        echo "  ./scripts/ojd signing install-profiles"
        echo "  ./scripts/ojd signing configure"
        exit 1
      fi
    fi

    if [[ -n "${PROFILE_TEAM:-}" && -n "${CERT_OU:-}" && "$PROFILE_TEAM" != "$CERT_OU" ]]; then
      echo ""
      echo "ERROR: Signing team mismatch for DriverKit extension."
      echo "  DEXT profile team: $PROFILE_TEAM"
      echo "  Apple Dev cert OU: $CERT_OU"
      exit 1
    fi
  fi

  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
  local XCODE_CLANG XCODE_CLANGXX
  XCODE_CLANG="$(xcrun --find clang)"
  XCODE_CLANGXX="$(xcrun --find clang++ 2>/dev/null || true)"
  [[ -n "$XCODE_CLANGXX" ]] || XCODE_CLANGXX="$(dirname "$XCODE_CLANG")/clang++"
  export PATH="$(dirname "$XCODE_CLANG"):/usr/bin:/bin:/usr/sbin:/sbin"
  echo "  Compiler: $("$XCODE_CLANG" --version | head -n 1)"
  mkdir -p "$DEXT_BUILD_DIR/Index.noindex/DataStore"

  local XCODEBUILD_SIGNING_ARGS=(
    CODE_SIGN_IDENTITY="$DEXT_BUILD_IDENTITY_XCODE"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    PROVISIONING_PROFILE_SPECIFIER="$DEXT_BUILD_PROFILE"
    CODE_SIGN_STYLE=Manual
  )
  if [[ "$OJD_ENV" == "release" ]]; then
    XCODEBUILD_SIGNING_ARGS=(
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
      CODE_SIGN_IDENTITY=
      PROVISIONING_PROFILE_SPECIFIER=
    )
  fi

  xcodebuild \
    -project "$DEXT_PROJECT" \
    -scheme "$DEXT_SCHEME" \
    -configuration "$DEXT_CONFIG" \
    -derivedDataPath "$DEXT_BUILD_DIR" \
    CC="$XCODE_CLANG" \
    CXX="$XCODE_CLANGXX" \
    "${XCODEBUILD_SIGNING_ARGS[@]}" \
    clean build

  [[ -d "$DEXT_PRODUCT" ]] || die ".dext not found at expected path: $DEXT_PRODUCT"

  if [[ -n "$DEXT_BUNDLE_VERSION" ]]; then
    plutil -replace CFBundleVersion -string "$DEXT_BUNDLE_VERSION" "$DEXT_PRODUCT/Info.plist"
  fi

  echo "Built: $DEXT_PRODUCT"

  local GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  local DEXT_SYSEXT="$GUI_APP/Contents/Library/SystemExtensions"
  local DEXT_BUNDLE_ID
  DEXT_BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$DEXT_PRODUCT/Info.plist")
  local DEXT_FILENAME="${DEXT_BUNDLE_ID}.dext"

  if [[ -d "$GUI_APP" ]]; then
    echo "Embedding dext into app bundle..."
    mkdir -p "$DEXT_SYSEXT"
    rm -rf "$DEXT_SYSEXT/$DEXT_FILENAME"
    rm -rf "$DEXT_SYSEXT/OpenJoystickVirtualHID.dext" 2>/dev/null || true
    cp -R "$DEXT_PRODUCT" "$DEXT_SYSEXT/$DEXT_FILENAME"

    local DEXT_EXEC_NAME
    DEXT_EXEC_NAME=$(ls "$DEXT_SYSEXT/$DEXT_FILENAME/" | grep -v -E 'Info\.plist|_CodeSignature|embedded\.provisionprofile' | head -1)
    chmod +x "$DEXT_SYSEXT/$DEXT_FILENAME/$DEXT_EXEC_NAME"
    plutil -replace CFBundleExecutable -string "$DEXT_EXEC_NAME" \
      "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist" 2>/dev/null \
      || plutil -insert CFBundleExecutable -string "$DEXT_EXEC_NAME" \
        "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist"

    local DEXT_ENTITLEMENTS_TMP="$PROJECT_DIR/.build/dext-entitlements.plist"
    if ! codesign -d --entitlements - --xml "$DEXT_SYSEXT/$DEXT_FILENAME" > "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null; then
      if [[ "$OJD_ENV" == "release" ]]; then
        cp "$DEXT_DIR/OpenJoystickVirtualHID.entitlements" "$DEXT_ENTITLEMENTS_TMP"
      else
        die "Failed to extract entitlements from dext"
      fi
    fi

    if [[ "$OJD_ENV" == "release" ]]; then
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Delete :get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
    fi

    local DEXT_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der --entitlements "$DEXT_ENTITLEMENTS_TMP")
    if [[ "$OJD_ENV" == "release" ]]; then
      DEXT_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${DEXT_SIGN_ARGS[@]}" "$DEXT_SYSEXT/$DEXT_FILENAME"

    [[ -f "$GUI_ENTITLEMENTS" ]] || resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
    local APP_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der --entitlements "$GUI_ENTITLEMENTS")
    if [[ "$OJD_ENV" == "release" ]]; then
      APP_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${APP_SIGN_ARGS[@]}" "$GUI_APP"

    if [[ "${OJD_SKIP_INSTALL:-0}" != "1" ]]; then
      echo "Installing to /Applications/OpenJoystickDriver.app..."
      rm -rf /Applications/OpenJoystickDriver.app
      cp -R "$GUI_APP" /Applications/
      echo "Copied to /Applications"
    else
      echo "Skipping /Applications install (OJD_SKIP_INSTALL=1)"
    fi
  else
    echo "ERROR: GUI app bundle not found at $GUI_APP"
    echo "Fix: run: ./scripts/ojd build dev"
    exit 1
  fi

  echo ""
  echo "DriverKit extension build complete."
  echo "  .dext: $DEXT_PRODUCT"
}
