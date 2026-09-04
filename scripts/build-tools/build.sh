#!/usr/bin/env bash
# Consolidated build/install script for OpenJoystickDriver.
#
# Human-facing entrypoint is: ./scripts/ojd
#
# Implements the build, install, and lint routes exposed by scripts/ojd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../platform/environment.sh"

# zsh has a 'log' builtin that shadows /usr/bin/log. Always use the full path.
LOG=/usr/bin/log

usage() {
  cat <<'TXT'
Usage:
  ./scripts/ojd build dev
  ./scripts/ojd build release
  ./scripts/ojd build dext

  ./scripts/ojd build install dev
  ./scripts/ojd build install release
  ./scripts/ojd build install-fast dev

Notes:
  - Full install upgrades the DriverKit system extension (may require reboot).
  - install-fast preserves the already-installed sysext (safe while streaming).
TXT
}

_require_codesign_identity() {
  if [[ "${GUI_IDENTITY:-"-"}" == "-" ]]; then
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
}

_codesign_identity_available() {
  local identity="$1"
  security find-identity -v -p codesigning 2>/dev/null | grep -Fi "$identity" >/dev/null
}

_ojd_application_job_labels() {
  launchctl print "gui/$(id -u)" 2>/dev/null \
    | sed -n 's/.*\(application\.com\.openjoystickdriver\.[A-Za-z0-9.-]*\).*/\1/p' \
    | sort -u
}

_ojd_application_job_is_running() {
  local label="$1"
  launchctl print "gui/$(id -u)/$label" 2>/dev/null \
    | grep -Eq '^[[:space:]]*(pid = [1-9][0-9]*|state = running)$'
}

_retire_ojd_application_jobs() {
  local domain="gui/$(id -u)"
  local labels=() label
  while IFS= read -r label; do
    [[ -n "$label" ]] && labels+=("$label")
  done < <(_ojd_application_job_labels)
  ((${#labels[@]} > 0)) || return 0

  echo "  Retiring ${#labels[@]} OJD LaunchServices application job(s)"
  for label in "${labels[@]}"; do
    launchctl kill SIGTERM "$domain/$label" 2>/dev/null || true
  done
  for _ in {1..50}; do
    local running=0
    for label in "${labels[@]}"; do
      _ojd_application_job_is_running "$label" && running=1
    done
    ((running == 0)) && return 0
    sleep 0.1
  done

  for label in "${labels[@]}"; do
    _ojd_application_job_is_running "$label" || continue
    echo "  OJD application job did not stop after SIGTERM; forcing $label"
    launchctl kill SIGKILL "$domain/$label" 2>/dev/null || true
  done
  for _ in {1..20}; do
    local running=0
    for label in "${labels[@]}"; do
      _ojd_application_job_is_running "$label" && running=1
    done
    ((running == 0)) && return 0
    sleep 0.1
  done

  for label in "${labels[@]}"; do
    _ojd_application_job_is_running "$label" || continue
    echo "  OJD application job survived SIGKILL; booting out $label"
    launchctl bootout "$domain/$label" 2>/dev/null || true
  done
  for _ in {1..20}; do
    local running=0
    for label in "${labels[@]}"; do
      _ojd_application_job_is_running "$label" && running=1
    done
    ((running == 0)) && return 0
    sleep 0.1
  done
  die "macOS left an unkillable OJD application job. Reboot once; OJD will recreate its app service automatically at login."
}

# ---------------------------------------------------------------------------
# Rebuild cleanup
# ---------------------------------------------------------------------------
clean_build_artifacts() {
  echo "=== CLEAN: clearing build artifacts ==="
  rm -rf "$PROJECT_DIR/.build/driverkit" 2>/dev/null || true
  rm -rf "$PROJECT_DIR/.build/debug/OpenJoystickDriver.app" 2>/dev/null || true
  rm -rf "$PROJECT_DIR/.build/arm64-apple-macosx" 2>/dev/null || true
  rm -rf "$PROJECT_DIR/.build/x86_64-apple-macosx" 2>/dev/null || true
  echo "  cleared generated DriverKit and application products"
}

nuke_all() {
  local SELF_PID=$$
  local DEXT_BUNDLE_ID="com.openjoystickdriver.XboxUSBDevice"
  local APP_PATH="/Applications/OpenJoystickDriver.app"

  echo "=== NUKE: killing every OJD process ==="
  _retire_ojd_application_jobs
  killall -9 OpenJoystickDriver 2>/dev/null && echo "  killed OpenJoystickDriver" || true
  killall -9 XboxUSBDevice 2>/dev/null && echo "  killed XboxUSBDevice" || true

  for pid in $(pgrep -f "$DEXT_BUNDLE_ID" 2>/dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    sudo kill -9 "$pid" 2>/dev/null && echo "  killed dext PID $pid" || true
  done

  for pid in $(pgrep -if "openjoystick" 2>/dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    kill -9 "$pid" 2>/dev/null && echo "  killed stray PID $pid" || true
    sudo kill -9 "$pid" 2>/dev/null || true
  done

  echo ""
  echo "=== NUKE: removing app from /Applications ==="
  if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH" 2>/dev/null || sudo rm -rf "$APP_PATH"
    echo "  removed $APP_PATH"
  else
    echo "  (not present)"
  fi

  echo ""
  echo "=== NUKE: removing application service logs ==="
  rm -rf "$HOME/Library/Logs/OpenJoystickDriver"
  echo "  removed"

  echo ""
  clean_build_artifacts

  echo ""
  echo "=== NUKE: verification ==="
  local STRAY
  STRAY=$(pgrep -if "openjoystick" 2>/dev/null | grep -v "^${SELF_PID}$" || true)
  if [[ -z "$STRAY" ]]; then
    echo "  ✓ No OJD processes running"
  else
    echo "  ✗ Still running: $STRAY"
  fi

  if [[ -d "$APP_PATH" ]]; then
    echo "  ✗ App still in /Applications"
  else
    echo "  ✓ App not in /Applications"
  fi

  echo ""
  echo "=== Sysext status (SIP prevents removal; the next install will replace it) ==="
  systemextensionsctl list 2>&1 | grep openjoystick || echo "  (none)"
}

# ---------------------------------------------------------------------------
# Build app (from scripts/build-dev.sh)
# ---------------------------------------------------------------------------
_profile_has_entitlement() {
  local profile="$1" key="$2"
  python3 - "$profile" "$key" <<'PY'
import os, sys, plistlib, subprocess
profile, key = sys.argv[1], sys.argv[2]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if p.returncode == 0 and p.stdout:
        return p.stdout
    return b""

try:
    raw = decode(profile)
    if not raw:
        print("decode_error")
        raise SystemExit(0)
    if b"<?xml" not in raw:
        print("decode_error")
        raise SystemExit(0)
    raw = raw[raw.index(b"<?xml") :]
    obj = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

ent = obj.get("Entitlements") or {}
print("true" if key in ent else "false")
PY
}

_profile_entitlement_value() {
  local profile="$1" key="$2"
  python3 - "$profile" "$key" <<'PY'
import plistlib, subprocess, sys
profile, key = sys.argv[1], sys.argv[2]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if p.returncode == 0 and p.stdout:
        return p.stdout
    return b""

try:
    raw = decode(profile)
    if not raw or b"<?xml" not in raw:
        print("decode_error")
        raise SystemExit(0)
    raw = raw[raw.index(b"<?xml") :]
    obj = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

ent = obj.get("Entitlements") or {}
keys = [key]
if key == "com.apple.application-identifier":
    keys.append("application-identifier")

for candidate in keys:
    value = ent.get(candidate)
    if isinstance(value, str):
        print(value)
        raise SystemExit(0)

print("missing")
PY
}

_require_profile_entitlement() {
  local profile="$1" key="$2" what="$3" fix="$4"
  local ok
  ok="$(_profile_has_entitlement "$profile" "$key" || echo "false")"
  if [[ "$ok" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not decode provisioning profile to check entitlements."
    echo "  profile: $profile"
    echo ""
    echo "Fix:"
    echo "  1) Install profiles: ./scripts/ojd signing install-profiles"
    echo "  2) Audit profiles:   ./scripts/ojd signing audit"
    exit 1
  fi
  if [[ "$ok" != "true" ]]; then
    echo ""
    echo "ERROR: Provisioning profile is missing entitlement: $key"
    echo "  profile: $profile"
    echo "  affects: $what"
    echo ""
    echo "$fix"
    exit 1
  fi
}

_require_profile_entitlement_value() {
  local profile="$1" key="$2" expected="$3" what="$4" fix="$5"
  local actual
  actual="$(_profile_entitlement_value "$profile" "$key" || echo "missing")"
  if [[ "$actual" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not decode provisioning profile to check entitlements."
    echo "  profile: $profile"
    echo ""
    echo "Fix:"
    echo "  1) Install profiles: ./scripts/ojd signing install-profiles"
    echo "  2) Audit profiles:   ./scripts/ojd signing audit"
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo ""
    echo "ERROR: Provisioning profile entitlement value mismatch: $key"
    echo "  profile: $profile"
    echo "  affects: $what"
    echo "  expected: $expected"
    echo "  actual: $actual"
    echo ""
    echo "$fix"
    exit 1
  fi
}

_signed_entitlement_value() {
  local target="$1" key="$2"
  python3 - "$target" "$key" <<'PY'
import plistlib, subprocess, sys

target, key = sys.argv[1], sys.argv[2]
result = subprocess.run(
    ["codesign", "-d", "--entitlements", "-", "--xml", target],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)
if result.returncode != 0 or not result.stdout or b"<?xml" not in result.stdout:
    print("decode_error")
    raise SystemExit(0)

try:
    raw = result.stdout[result.stdout.index(b"<?xml") :]
    entitlements = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

value = entitlements.get(key, "missing")
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, str):
    print(value)
else:
    print("missing" if value == "missing" else str(value))
PY
}

_require_signed_entitlement_value() {
  local target="$1" key="$2" expected="$3" what="$4" fix="$5"
  local actual
  actual="$(_signed_entitlement_value "$target" "$key" || echo "missing")"
  if [[ "$actual" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not read signed entitlements from bundle."
    echo "  path: $target"
    echo "  affects: $what"
    echo ""
    echo "$fix"
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo ""
    echo "ERROR: Signed bundle entitlement value mismatch: $key"
    echo "  path: $target"
    echo "  affects: $what"
    echo "  expected: $expected"
    echo "  actual: $actual"
    echo ""
    echo "$fix"
    exit 1
  fi
}

source "$SCRIPT_DIR/driverkit.sh"
source "$SCRIPT_DIR/bundles.sh"

next_dext_bundle_version() {
  local max_version=0
  local candidate

  candidate=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext/Info.plist \
    2>/dev/null || echo "")
  if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
    max_version="$candidate"
  fi

  while IFS= read -r candidate; do
    if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
      max_version="$candidate"
    fi
  done < <(
    systemextensionsctl list 2>/dev/null \
      | sed -n 's/.*com\.openjoystickdriver\.XboxUSBDevice ([^/][^/]*\/\([0-9][0-9]*\)).*/\1/p'
  )

  echo $((max_version + 1))
}

install_fast() {
  local APP_DST="/Applications/OpenJoystickDriver.app"
  local APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  [[ -d "$APP_DST" ]] || die "$APP_DST not found. Run ./scripts/ojd build install dev once first."

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
  ojd_sign "$APP_SRC" --entitlements "$GUI_ENTITLEMENTS"
  echo "  Verifying signature (strict)..."
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_SRC" >/dev/null 2>&1 \
    || die "App signature verification failed after re-sign (run codesign --verify to see why)."
  echo "  ✓ Signature OK"

  echo ""
  echo "=== Step 3: Install app (without triggering sysext upgrade) ==="
  python3 "$PROJECT_DIR/scripts/build-tools/install_app.py" "$APP_SRC"
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
      /usr/bin/env bash "$SCRIPT_DIR/../release/notarize.sh" submit
  fi

  echo ""
  echo "=== Step 4.5: Install and verify app ==="
  python3 "$PROJECT_DIR/scripts/build-tools/install_app.py" \
    --retire-driverkit \
    "$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  echo ""
  echo "=== Step 5: Submit sysext activation ==="
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless extension enable; then
    echo "  ✓ Sysext activation request submitted"
  else
    echo "  ✗ Sysext activation request failed"
    echo "    Fix: run: $APP_BIN --headless extension enable"
  fi

  echo ""
  echo "=== Step 6: Wait for sysext activation ==="
  echo ""

  local INSTALLED_DEXT_INFO
  INSTALLED_DEXT_INFO="/Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext/Info.plist"
  local NEW_SHORT_VERSION NEW_BUILD_VERSION
  NEW_SHORT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INSTALLED_DEXT_INFO" 2>/dev/null || echo "")
  NEW_BUILD_VERSION=$(plutil -extract CFBundleVersion raw "$INSTALLED_DEXT_INFO" 2>/dev/null || echo "")
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
    printf "  …waiting for sysext %s (%s) (%ds)\n" "$NEW_SHORT_VERSION" "$NEW_BUILD_VERSION" "$SYSEXT_ELAPSED"
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
      printf "  …%ds\n" "$ELAPSED"
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

run_lint() {
  command -v swiftlint >/dev/null 2>&1 || die "swiftlint not found (brew install swiftlint)"
  cd "$PROJECT_DIR"

  # SwiftLint's implicit recursive walk includes ignored working-tree paths
  # (for example, disposable external checkouts under .tmp). Build the input
  # list from tracked and non-ignored Swift files instead, while retaining
  # untracked repository-owned files during local development.
  local lint_paths=()
  local lint_path
  while IFS= read -r -d '' lint_path; do
    lint_paths+=("$lint_path")
  done < <(git -C "$PROJECT_DIR" ls-files -z --cached --others --exclude-standard -- '*.swift')
  # Keep a useful fallback if the checkout metadata is unavailable. In a
  # normal repository Package.swift is already returned by the pathspec.
  if [ "${#lint_paths[@]}" -eq 0 ]; then
    lint_paths+=("Package.swift")
  fi

  local framework_path
  framework_path="$(xcrun --show-sdk-path 2>/dev/null)/../../usr/lib"
  [ -d "$framework_path/sourcekitdInProc.framework" ] || framework_path=""
  if [ -n "$framework_path" ]; then
    DYLD_FRAMEWORK_PATH="$framework_path" swiftlint lint --no-cache --strict "${lint_paths[@]}"
  else
    swiftlint lint --no-cache --strict "${lint_paths[@]}"
  fi
}

cmd="${1:-}"
sub="${2:-}"

case "$cmd" in
  ""|-h|--help|help)
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
      dev|release)
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
  install)
    case "$sub" in
      dev|release)
        install_full
        ;;
      *)
        die "Unknown: install $sub (expected: dev | release)"
        ;;
    esac
    ;;
  install-fast)
    case "$sub" in
      dev)
        install_fast
        ;;
      *)
        die "Unknown: install-fast $sub (expected: dev)"
        ;;
    esac
    ;;
  *)
    die "Unknown command: $cmd"
    ;;
esac
