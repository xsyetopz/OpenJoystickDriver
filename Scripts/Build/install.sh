#!/usr/bin/env bash
# Installation workflows exposed only through ./Scripts/ojd commands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build.sh"

# The commit's build number with a development stage one above any installed
# development build of it, so reinstalling the same commit replaces the DEXT.
next_dext_bundle_version() {
  local installed=()
  local candidate

  candidate=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext/Info.plist \
    2>/dev/null || echo "")
  [[ -n "$candidate" ]] && installed+=("$candidate")

  while IFS= read -r candidate; do
    installed+=("$candidate")
  done < <(
    systemextensionsctl list 2>/dev/null \
      | sed -n 's/.*com\.openjoystickdriver\.XboxUSBDevice ([^/][^/]*\/\([^)]*\)).*/\1/p'
  )

  python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" --next-dev \
    "$(python3 "$PROJECT_DIR/Scripts/Release/bundle_version.py" "$PROJECT_DIR")" \
    ${installed[@]+"${installed[@]}"}
}

# True when systemextensionsctl lists the DEXT at this version, in any state.
sysext_listed() {
  local listing
  listing="$(systemextensionsctl list 2>&1 || true)"
  [[ "$listing" == *"com.openjoystickdriver.XboxUSBDevice ($1/$2)"* ]]
}

# App-only install. Not a TCC or permission probe: the copy-then-re-sign of the
# host always rewrites the code signature. If that designated requirement is
# cdhash-pinned or leaf-pinned, Input Monitoring and Accessibility rows go
# stale and need a re-grant. Host signing uses a team+identifier DR so
# same-team rebuilds keep those grants. xattr quarantine and ditto do not.
install_fast() {
  local APP_DST="/Applications/OpenJoystickDriver.app"
  local APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  [[ -d "$APP_DST" ]] || die "$APP_DST not found. Run ./Scripts/ojd build install dev once first."

  echo "=== Step 1: Build app (no dext) ==="
  build_app_bundle

  echo ""
  echo "=== Step 2: Preserve embedded system extension ==="
  local DEXT_DIR_DST="$APP_DST/Contents/Library/SystemExtensions"
  local DEXT_DIR_SRC="$APP_SRC/Contents/Library/SystemExtensions"
  if [[ -d "$DEXT_DIR_DST" ]]; then
    rm -rf "$DEXT_DIR_SRC" 2>/dev/null || true
    mkdir -p "$DEXT_DIR_SRC"
    cp -R "$DEXT_DIR_DST/"* "$DEXT_DIR_SRC/" 2>/dev/null || true
    echo "  Preserved: $DEXT_DIR_DST"
  else
    echo "  WARN: No SystemExtensions folder in $APP_DST (sysext may not be installed yet)"
  fi

  echo ""
  echo "=== Step 2.5: Re-sign app bundle (required) ==="
  [[ -f "$GUI_ENTITLEMENTS" ]] || resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
  _require_codesign_identity
  echo "  Signing: $APP_SRC"
  OJD_ACTIVE_SIGN_IDENTITY="$GUI_IDENTITY" ojd_sign "$APP_SRC" --entitlements "$GUI_ENTITLEMENTS"
  echo "  Verifying signature (strict)..."
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_SRC" >/dev/null 2>&1 \
    || die "App signature verification failed after re-sign (run codesign --verify to see why)."
  echo "  ✓ Signature OK"

  echo ""
  echo "=== Step 3: Install app (without triggering sysext upgrade) ==="
  python3 "$PROJECT_DIR/Scripts/Build/install_app.py" "$APP_SRC"
}

install_full() {
  echo "=== Step 1: Clean build products without stopping the installed app ==="
  clean_build_artifacts

  echo ""
  echo "=== Step 2: Build app ==="
  build_app_bundle

  echo ""
  echo "=== Step 3: Build dext ==="
  local DEXT_VER
  DEXT_VER="$(next_dext_bundle_version)"
  echo "  Using CFBundleVersion=$DEXT_VER"
  DEXT_BUNDLE_VERSION="$DEXT_VER" build_dext_bundle

  echo ""
  echo "=== Step 4: Verify bundle IDs ==="
  local APP_ID DEXT_ID
  APP_ID=$(plutil -extract CFBundleIdentifier raw .build/debug/OpenJoystickDriver.app/Contents/Info.plist 2>/dev/null || echo "MISSING")
  DEXT_ID=$(plutil -extract CFBundleIdentifier raw ".build/debug/OpenJoystickDriver.app/Contents/Library/SystemExtensions/${APP_ID}.XboxUSBDevice.dext/Info.plist" 2>/dev/null || echo "MISSING")
  echo "  App:  $APP_ID"
  echo "  Dext: $DEXT_ID"
  [[ "$DEXT_ID" == "$APP_ID"* ]] || die "PREFIX MISMATCH: dext will not be found in app bundle"

  if [[ "$OJD_ENV" == "release" ]]; then
    echo ""
    echo "=== Notarizing ==="
    OJD_NOTARIZE_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app" \
      /usr/bin/env bash "$SCRIPT_DIR/../Release/notarize.sh" submit
  fi

  echo ""
  echo "=== Step 4.5: Install and verify app ==="
  python3 "$PROJECT_DIR/Scripts/Build/install_app.py" \
    --retire-driverkit \
    "$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  local INSTALLED_DEXT_INFO
  INSTALLED_DEXT_INFO="/Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext/Info.plist"
  local NEW_SHORT_VERSION NEW_BUILD_VERSION
  NEW_SHORT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INSTALLED_DEXT_INFO" 2>/dev/null || echo "")
  NEW_BUILD_VERSION=$(plutil -extract CFBundleVersion raw "$INSTALLED_DEXT_INFO" 2>/dev/null || echo "")

  echo ""
  echo "=== Step 5: Submit sysext activation ==="
  # The launched app requests activation itself when its embedded DEXT differs
  # from the installed one. sysextd rejects a second request for the same
  # extension while the first is in progress (OSSystemExtensionErrorDomain 4),
  # so submit one only when the app's request does not appear.
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local REQUEST_WAIT=0
  until sysext_listed "$NEW_SHORT_VERSION" "$NEW_BUILD_VERSION" || (( REQUEST_WAIT >= 10 )); do
    sleep 1
    REQUEST_WAIT=$(( REQUEST_WAIT + 1 ))
  done
  if sysext_listed "$NEW_SHORT_VERSION" "$NEW_BUILD_VERSION"; then
    echo "  ✓ The app requested activation of ${NEW_SHORT_VERSION} (${NEW_BUILD_VERSION})"
  # argv[0] "ojd" selects the command line in the app executable.
  elif (exec -a ojd "$APP_BIN" extension activate); then
    echo "  ✓ Sysext activation request submitted"
  else
    echo "  ✗ Sysext activation request failed"
    echo "    Fix: run: ojd extension activate"
  fi

  echo ""
  echo "=== Step 6: Wait for sysext activation ==="
  echo ""

  local SYSEXT_TIMEOUT=30 SYSEXT_ELAPSED=0
  while (( SYSEXT_ELAPSED < SYSEXT_TIMEOUT )); do
    sleep 2
    SYSEXT_ELAPSED=$(( SYSEXT_ELAPSED + 2 ))
    if systemextensionsctl list 2>&1 \
      | grep -F "com.openjoystickdriver.XboxUSBDevice (${NEW_SHORT_VERSION}/${NEW_BUILD_VERSION})" \
      | grep -q "activated enabled"; then
      echo "  ✓ Sysext ${NEW_SHORT_VERSION} (${NEW_BUILD_VERSION}) activated after ${SYSEXT_ELAPSED}s"
      break
    fi
    printf "  ...waiting for sysext %s (%s) (%ds)\n" "$NEW_SHORT_VERSION" "$NEW_BUILD_VERSION" "$SYSEXT_ELAPSED"
  done
  if (( SYSEXT_ELAPSED >= SYSEXT_TIMEOUT )); then
    echo "  ⚠ Sysext ${NEW_SHORT_VERSION} (${NEW_BUILD_VERSION}) not activated after ${SYSEXT_TIMEOUT}s. Continuing anyway."
  fi

  echo ""
  echo "=== Step 7: Wait for dext start ==="
  if ! ojd_microsoft_driverkit_interface_connected; then
    echo "  ✓ Dext is activated and idle; no entitled Microsoft USB interface is connected."
  else
    local TIMEOUT=60 ELAPSED=0
    while (( ELAPSED < TIMEOUT )); do
      sleep 3
      ELAPSED=$(( ELAPSED + 3 ))
      if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null | grep -q "start fail"; then
        echo "  ✗ Kernel DK log shows 'start fail' after ${ELAPSED}s"
        break
      fi
      if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null | grep -q "user server timeout"; then
        echo "  ✗ Kernel DK log shows 'user server timeout' after ${ELAPSED}s"
        break
      fi
      if pgrep -x XboxUSBDevice >/dev/null 2>&1; then
        echo "  ✓ Dext process detected after ${ELAPSED}s"
        break
      fi
      printf "  ...%ds\n" "$ELAPSED"
    done
    if (( ELAPSED >= TIMEOUT )); then
      echo "  ⚠ Timed out after ${TIMEOUT}s while an entitled Microsoft USB interface was connected."
    fi
  fi

  echo ""
  echo ""
  echo "=== Step 8: Diagnostics ==="
  echo "--- Dext os_log (last 60s) ---"
  $LOG show --last 60s --predicate 'eventMessage CONTAINS "XboxUSBDevice"' --info --debug --style compact 2>/dev/null || echo "(none)"
  echo ""
  echo "--- Kernel DK logs (last 60s) ---"
  $LOG show --last 60s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null || echo "(none)"
  echo ""
  echo "--- Sysext status ---"
  systemextensionsctl list 2>&1 || true
  echo ""
  echo "--- Application service log (fresh) ---"
  tail -10 "$HOME/Library/Logs/OpenJoystickDriver/OpenJoystickDriver.out.log" 2>/dev/null || echo "(no application service log)"
}

cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  install)
    [[ "$sub" == "dev" || "$sub" == "release" ]] || die "Unknown: install $sub (expected: dev | release)"
    install_full
    ;;
  install-fast)
    [[ "$sub" == "dev" ]] || die "Unknown: install-fast $sub (expected: dev)"
    install_fast
    ;;
  *) die "Unknown install command: $cmd" ;;
esac
