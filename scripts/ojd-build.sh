#!/usr/bin/env bash
# Consolidated build/rebuild script for OpenJoystickDriver.
#
# Human-facing entrypoint is: ./scripts/ojd
#
# This file exists so the repo does not devolve into 20+ half-overlapping scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

# zsh has a 'log' builtin that shadows /usr/bin/log -- always use full path
LOG=/usr/bin/log

die() {
  echo "ERROR: $*" >&2
  exit 2
}

usage() {
  cat << 'TXT'
Usage:
  ./scripts/ojd build dev
  ./scripts/ojd build release
  ./scripts/ojd build dext

  ./scripts/ojd rebuild dev
  ./scripts/ojd rebuild release
  ./scripts/ojd rebuild-fast dev

Notes:
  - Full rebuild upgrades the DriverKit system extension (may require reboot).
  - rebuild-fast preserves the already-installed sysext (safe while streaming).
TXT
}

_require_codesign_identity() {
  if [[ "${GUI_IDENTITY:-"-"}" == "-" || "${DAEMON_IDENTITY:-"-"}" == "-" ]]; then
    echo "ERROR: CODESIGN_IDENTITY not set."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi
  if ! _codesign_identity_available "$GUI_IDENTITY"; then
    echo "ERROR: GUI signing identity is not available/trusted in Keychain: $GUI_IDENTITY"
    echo "Fix: install the matching signing certificate/private key, then run:"
    echo "  ./scripts/ojd signing configure"
    exit 1
  fi
  if ! _codesign_identity_available "$DAEMON_IDENTITY"; then
    echo "ERROR: daemon signing identity is not available/trusted in Keychain: $DAEMON_IDENTITY"
    echo "Fix: install the matching signing certificate/private key, then run:"
    echo "  ./scripts/ojd signing configure"
    exit 1
  fi
}

_codesign_identity_available() {
  local identity="$1"
  security find-identity -v -p codesigning 2> /dev/null | grep -Fi "$identity" > /dev/null
}

# ---------------------------------------------------------------------------
# Nuke (from scripts/nuke.sh)
# ---------------------------------------------------------------------------
nuke_all() {
  local SELF_PID=$$
  local DEXT_BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
  local DAEMON_LABEL="com.openjoystickdriver.daemon"
  local APP_PATH="/Applications/OpenJoystickDriver.app"

  echo "=== NUKE: killing every OJD process ==="
  killall -9 OpenJoystickDriver 2> /dev/null && echo "  killed OpenJoystickDriver" || true
  killall -9 OpenJoystickDriverDaemon 2> /dev/null && echo "  killed OpenJoystickDriverDaemon" || true
  killall -9 OpenJoystickVirtualHID 2> /dev/null && echo "  killed OpenJoystickVirtualHID" || true

  for pid in $(pgrep -f "$DEXT_BUNDLE_ID" 2> /dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    sudo kill -9 "$pid" 2> /dev/null && echo "  killed dext PID $pid" || true
  done

  for pid in $(pgrep -if "openjoystick" 2> /dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    kill -9 "$pid" 2> /dev/null && echo "  killed stray PID $pid" || true
    sudo kill -9 "$pid" 2> /dev/null || true
  done

  echo ""
  echo "=== NUKE: removing daemon from launchd ==="
  if [[ -x "$APP_PATH/Contents/MacOS/OpenJoystickDriver" ]]; then
    "$APP_PATH/Contents/MacOS/OpenJoystickDriver" --headless remove &&
      echo "  daemon uninstall succeeded" || true
  fi
  launchctl bootout "gui/$(id -u)/$DAEMON_LABEL" 2> /dev/null && echo "  bootout succeeded" || true
  launchctl remove "$DAEMON_LABEL" 2> /dev/null && echo "  remove succeeded" || true
  launchctl unload ~/Library/LaunchAgents/${DAEMON_LABEL}.plist 2> /dev/null && echo "  unload succeeded" || true

  echo ""
  echo "=== NUKE: removing LaunchAgent plist ==="
  rm -f ~/Library/LaunchAgents/${DAEMON_LABEL}.plist && echo "  removed" || true

  echo ""
  echo "=== NUKE: removing app from /Applications ==="
  if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH" 2> /dev/null || sudo rm -rf "$APP_PATH"
    echo "  removed $APP_PATH"
  else
    echo "  (not present)"
  fi

  echo ""
  echo "=== NUKE: truncating daemon logs ==="
  : > /tmp/${DAEMON_LABEL}.out 2> /dev/null || true
  : > /tmp/${DAEMON_LABEL}.err 2> /dev/null || true
  echo "  truncated"

  echo ""
  echo "=== NUKE: clearing build artifacts ==="
  rm -rf "$SCRIPT_DIR/../.build/dext" 2> /dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/debug/OpenJoystickDriver.app" 2> /dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/arm64-apple-macosx" 2> /dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/x86_64-apple-macosx" 2> /dev/null || true
  echo "  cleared .build/dext and .build/debug app"

  echo ""
  echo "=== NUKE: clearing Xcode derived data for dext ==="
  rm -rf ~/Library/Developer/Xcode/DerivedData/OpenJoystickVirtualHID-* 2> /dev/null || true
  echo "  cleared"

  echo ""
  echo "=== NUKE: verification ==="
  local STRAY
  STRAY=$(pgrep -if "openjoystick" 2> /dev/null | grep -v "^${SELF_PID}$" || true)
  if [[ -z "$STRAY" ]]; then
    echo "  ✓ No OJD processes running"
  else
    echo "  ✗ Still running: $STRAY"
  fi

  if launchctl list 2> /dev/null | grep -q "$DAEMON_LABEL"; then
    echo "  ✗ Daemon still in launchd"
  else
    echo "  ✓ Daemon not in launchd"
  fi

  if [[ -d "$APP_PATH" ]]; then
    echo "  ✗ App still in /Applications"
  else
    echo "  ✓ App not in /Applications"
  fi

  echo ""
  echo "=== Sysext status (cannot remove with SIP -- will be replaced on next install) ==="
  systemextensionsctl list 2>&1 | grep openjoystick || echo "  (none)"
}

# ---------------------------------------------------------------------------
# Build app (from scripts/build-dev.sh)
# ---------------------------------------------------------------------------
source "$SCRIPT_DIR/ojd-build-entitlements.sh"
source "$SCRIPT_DIR/ojd-build-bundles.sh"

next_dext_bundle_version() {
  local max_version=0
  local candidate

  candidate=$(plutil -extract CFBundleVersion raw "$PROJECT_DIR/DriverKitExtension/Info.plist" 2> /dev/null || echo "")
  if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
    max_version="$candidate"
  fi

  candidate=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext/Info.plist \
    2> /dev/null || echo "")
  if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
    max_version="$candidate"
  fi

  while IFS= read -r candidate; do
    if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
      max_version="$candidate"
    fi
  done < <(
    systemextensionsctl list 2> /dev/null |
      sed -n 's/.*com\.openjoystickdriver\.VirtualHIDDevice (1\.0\/\([0-9][0-9]*\)).*/\1/p'
  )

  echo $((max_version + 1))
}

rebuild_fast() {
  local APP_DST="/Applications/OpenJoystickDriver.app"
  local APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  [[ -d "$APP_DST" ]] || die "$APP_DST not found. Run ./scripts/ojd rebuild dev once first."

  echo "=== Step 1: Build app (no dext) ==="
  build_app_bundle

  echo ""
  echo "=== Step 2: Preserve embedded system extension ==="
  local DEXT_DIR_DST="$APP_DST/Contents/Library/SystemExtensions"
  local DEXT_DIR_SRC="$APP_SRC/Contents/Library/SystemExtensions"
  if [[ -d "$DEXT_DIR_DST" ]]; then
    rm -rf "$DEXT_DIR_SRC" 2> /dev/null || true
    mkdir -p "$DEXT_DIR_SRC"
    cp -R "$DEXT_DIR_DST/"* "$DEXT_DIR_SRC/" 2> /dev/null || true
    echo "  Preserved: $DEXT_DIR_DST"
  else
    echo "  WARN: No SystemExtensions folder in $APP_DST (sysext may not be installed yet)"
  fi

  echo ""
  echo "=== Step 2.5: Re-sign app bundle (required) ==="
  [[ -f "$GUI_ENTITLEMENTS" ]] || resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
  _require_codesign_identity
  echo "  Signing: $APP_SRC"
  ojd_sign "$APP_SRC" --entitlements "$GUI_ENTITLEMENTS"
  echo "  Verifying signature (strict)..."
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_SRC" > /dev/null 2>&1 ||
    die "App signature verification failed after re-sign (run codesign --verify to see why)."
  echo "  ✓ Signature OK"

  echo ""
  echo "=== Step 3: Install app (without triggering sysext upgrade) ==="
  rm -rf "$APP_DST"
  cp -R "$APP_SRC" "$APP_DST"
  xattr -dr com.apple.quarantine "$APP_DST" 2> /dev/null || true
  echo "  Copied to $APP_DST"

  echo ""
  echo "=== Step 4: Restart daemon ==="
  : > /tmp/com.openjoystickdriver.daemon.out 2> /dev/null || true
  : > /tmp/com.openjoystickdriver.daemon.err 2> /dev/null || true
  local APP_BIN="$APP_DST/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless restart; then
    echo "  ✓ Daemon restarted"
  else
    echo "  ✗ Daemon restart failed"
    echo "    Fix: run: $APP_BIN --headless install"
  fi

  echo ""
  echo "=== Step 5: Launch app ==="
  open "$APP_DST" || true
  echo "  Launched OpenJoystickDriver"
}

rebuild_full() {
  echo "=== Step 1: Nuke all stale state ==="
  nuke_all

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
  APP_ID=$(plutil -extract CFBundleIdentifier raw .build/debug/OpenJoystickDriver.app/Contents/Info.plist 2> /dev/null || echo "MISSING")
  DEXT_ID=$(plutil -extract CFBundleIdentifier raw ".build/debug/OpenJoystickDriver.app/Contents/Library/SystemExtensions/${APP_ID}.VirtualHIDDevice.dext/Info.plist" 2> /dev/null || echo "MISSING")
  echo "  App:  $APP_ID"
  echo "  Dext: $DEXT_ID"
  [[ "$DEXT_ID" == "$APP_ID"* ]] || die "PREFIX MISMATCH -- dext will not be found in app bundle"

  if [[ "$OJD_ENV" == "release" ]]; then
    echo ""
    echo "=== Notarizing ==="
    /usr/bin/env bash "$SCRIPT_DIR/ojd-notarize.sh" submit
  fi

  echo ""
  echo "=== Step 5: Submit sysext activation ==="
  : > /tmp/com.openjoystickdriver.daemon.out 2> /dev/null || true
  : > /tmp/com.openjoystickdriver.daemon.err 2> /dev/null || true
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless ext install; then
    echo "  ✓ Sysext activation request submitted"
  else
    echo "  ✗ Sysext activation request failed"
    echo "    Fix: run: $APP_BIN --headless ext install"
  fi

  echo ""
  echo "=== Step 6: Wait for sysext activation ==="
  echo ""

  local NEW_VERSION
  NEW_VERSION=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext/Info.plist 2> /dev/null || echo "")
  local SYSEXT_TIMEOUT=30 SYSEXT_ELAPSED=0
  while ((SYSEXT_ELAPSED < SYSEXT_TIMEOUT)); do
    sleep 2
    SYSEXT_ELAPSED=$((SYSEXT_ELAPSED + 2))
    if systemextensionsctl list 2>&1 | grep -q "1.0/${NEW_VERSION}.*activated enabled"; then
      echo "  ✓ Sysext v${NEW_VERSION} activated after ${SYSEXT_ELAPSED}s"
      break
    fi
    printf "  …waiting for sysext v%s (%ds)\n" "$NEW_VERSION" "$SYSEXT_ELAPSED"
  done
  if ((SYSEXT_ELAPSED >= SYSEXT_TIMEOUT)); then
    echo "  ⚠ Sysext v${NEW_VERSION} not activated after ${SYSEXT_TIMEOUT}s -- continuing anyway"
  fi

  echo ""
  echo "=== Step 7: Wait for dext start ==="
  local TIMEOUT=60 ELAPSED=0
  while ((ELAPSED < TIMEOUT)); do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2> /dev/null | grep -q "start fail"; then
      echo "  ✗ Kernel DK log shows 'start fail' after ${ELAPSED}s"
      break
    fi
    if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2> /dev/null | grep -q "user server timeout"; then
      echo "  ✗ Kernel DK log shows 'user server timeout' after ${ELAPSED}s"
      break
    fi
    if $LOG show --last 10s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID:"' --info --debug --style compact 2> /dev/null | grep -q "OpenJoystickVirtualHID:"; then
      echo "  ✓ Dext logs detected after ${ELAPSED}s"
      break
    fi
    printf "  …%ds\n" "$ELAPSED"
  done
  if ((ELAPSED >= TIMEOUT)); then
    echo "  ⚠ Timed out after ${TIMEOUT}s -- no dext logs or start fail detected"
  fi

  echo ""
  echo "=== Step 8: Restart daemon ==="
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless restart; then
    echo "  ✓ Daemon restarted"
  else
    echo "  ✗ Daemon restart failed"
    echo "    Fix: run: $APP_BIN --headless install"
  fi

  echo ""
  echo "=== Step 9: Diagnostics ==="
  echo "--- Dext os_log (last 60s) ---"
  $LOG show --last 60s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID"' --info --debug --style compact 2> /dev/null || echo "(none)"
  echo ""
  echo "--- Kernel DK logs (last 60s) ---"
  $LOG show --last 60s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2> /dev/null || echo "(none)"
  echo ""
  echo "--- Sysext status ---"
  systemextensionsctl list 2>&1 || true
  echo ""
  echo "--- Daemon log (fresh) ---"
  tail -10 /tmp/com.openjoystickdriver.daemon.out 2> /dev/null || echo "(no daemon log)"
}

run_lint() {
  command -v swiftlint > /dev/null 2>&1 || die "swiftlint not found (brew install swiftlint)"
  cd "$PROJECT_DIR"
  swiftlint lint --no-cache --strict --baseline .swiftlint-baseline.json
}

cmd="${1:-}"
sub="${2:-}"

case "$cmd" in
  "" | -h | --help | help)
    usage
    exit 0
    ;;
  nuke)
    nuke_all
    ;;
  lint)
    run_lint
    ;;
  build)
    case "$sub" in
      dev | release)
        build_app_bundle
        ;;
      dext)
        build_dext_bundle
        ;;
      *)
        die "Unknown: build $sub (expected: dev | release | dext)"
        ;;
    esac
    ;;
  rebuild)
    case "$sub" in
      dev | release)
        rebuild_full
        ;;
      *)
        die "Unknown: rebuild $sub (expected: dev | release)"
        ;;
    esac
    ;;
  rebuild-fast)
    case "$sub" in
      dev)
        rebuild_fast
        ;;
      *)
        die "Unknown: rebuild-fast $sub (expected: dev)"
        ;;
    esac
    ;;
  *)
    die "Unknown command: $cmd"
    ;;
esac
