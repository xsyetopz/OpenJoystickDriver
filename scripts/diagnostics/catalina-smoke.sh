#!/usr/bin/env bash
# Smoke-test the foreground OpenJoystickDriver.app bundle on macOS 10.15.
set -euo pipefail

APP_PATH="${1:-/Applications/OpenJoystickDriver.app}"
failures=0

pass() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; failures=$((failures + 1)); }
note() { echo "[INFO] $*"; }

require_file() {
  if [[ -f "$1" ]]; then pass "found $1"; else fail "missing $1"; fi
}

plist_value() {
  /usr/bin/plutil -extract "$1" raw "$2" 2>/dev/null || true
}

min_macos_for() {
  /usr/bin/otool -l "$1" 2>/dev/null | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build = 1; in_min = 0; next }
    in_build && $1 == "minos" { print $2; exit }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { in_min = 1; in_build = 0; next }
    in_min && $1 == "version" { print $2; exit }
  ' || true
}

echo "OpenJoystickDriver Catalina foreground smoke test"
echo "app: $APP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_BIN="$APP_PATH/Contents/MacOS/OpenJoystickDriver"
ICON="$APP_PATH/Contents/Resources/OpenJoystickDriver.icns"

[[ -d "$APP_PATH" ]] || { fail "app bundle not found: $APP_PATH"; exit 1; }
require_file "$INFO_PLIST"
require_file "$APP_BIN"
require_file "$ICON"

minimum="$(plist_value LSMinimumSystemVersion "$INFO_PLIST")"
min_binary="$(min_macos_for "$APP_BIN")"
archs="$(/usr/bin/lipo -archs "$APP_BIN" 2>/dev/null || true)"
note "LSMinimumSystemVersion: ${minimum:-missing}"
note "binary minimum: ${min_binary:-missing}"
note "architectures: ${archs:-missing}"
[[ "$minimum" == "10.15" ]] || fail "LSMinimumSystemVersion is not 10.15"
[[ "$min_binary" == "10.15" ]] || fail "binary does not target macOS 10.15"
[[ "$archs" == *"x86_64"* ]] || fail "application is missing x86_64"

if find "$APP_PATH/Contents" -path '*/LaunchAgents/*' -o -name 'OpenJoystickDriverDaemon*' |
  /usr/bin/grep -q .
then
  fail "bundle contains an obsolete agent or helper"
else
  pass "bundle contains only the main runtime identity"
fi

"$APP_BIN" --headless --help >/dev/null || fail "headless CLI failed to start"

if [[ "$failures" -eq 0 ]]; then
  pass "Catalina foreground checks passed"
else
  fail "$failures check(s) failed"
fi
exit "$failures"
