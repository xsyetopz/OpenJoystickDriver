#!/usr/bin/env bash
# Build workflows for OpenJoystickDriver.
#
# Human-facing entrypoint is: ./Scripts/ojd
#
# Implements the build routes exposed by Scripts/ojd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../Platform/environment.sh"

# zsh has a 'log' builtin that shadows /usr/bin/log. Always use the full path.
LOG=/usr/bin/log
export LOG

usage() {
  cat <<'TXT'
Usage:
  ./Scripts/ojd build dev
  ./Scripts/ojd build release
  ./Scripts/ojd build dext
TXT
}

_require_codesign_identity() {
  if [[ "${GUI_IDENTITY:-"-"}" == "-" ]]; then
    echo "ERROR: CODESIGN_IDENTITY not set."
    echo "Fix: run: ./Scripts/ojd signing configure"
    exit 1
  fi
  if ! _codesign_identity_available "$GUI_IDENTITY"; then
    echo "ERROR: GUI signing identity is not available/trusted in Keychain: $GUI_IDENTITY"
    echo "Fix: install the matching signing certificate/private key, then run:"
    echo "  ./Scripts/ojd signing configure"
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

_ojd_process_is_alive() {
  local pid="$1"
  local state rss
  read -r state rss < <(ps -p "$pid" -o state=,rss= 2>/dev/null) || return 1
  [[ -n "$state" && -n "$rss" ]] || return 1
  # macOS reports exiting leftovers as Z, E, or ?E with rss 0.
  [[ "$state" == *Z* || "$state" == *E* ]] && return 1
  ((rss > 0))
}

_ojd_application_job_is_running() {
  local label="$1"
  local output pid
  output="$(launchctl print "gui/$(id -u)/$label" 2>/dev/null)" || return 1
  pid="$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)[[:space:]]*$/\1/p' | head -n1)"
  if [[ -n "$pid" ]]; then
    _ojd_process_is_alive "$pid"
    return $?
  fi
  printf '%s\n' "$output" | grep -Eq '^[[:space:]]*state = running[[:space:]]*$'
}

_retire_ojd_application_jobs() {
  local domain
  domain="gui/$(id -u)"
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
  if ! pgrep -x OpenJoystickDriver >/dev/null 2>&1; then
    echo "  LaunchServices still lists a retired OJD job with no live process; continuing"
    return 0
  fi
  die "macOS left an unkillable OJD application job. Reboot once; OJD will recreate its app service automatically at login."
}

# ---------------------------------------------------------------------------
# Rebuild cleanup
# ---------------------------------------------------------------------------
clean_build_artifacts() {
  echo "=== CLEAN: clearing build artifacts ==="
  rm -rf "$PROJECT_DIR/.build/driverkit" 2>/dev/null || true
  rm -rf "$PROJECT_DIR/.build/debug/OpenJoystickDriver.app" 2>/dev/null || true
  rm -rf "$GUI_DERIVED_DATA/Build" 2>/dev/null || true
  echo "  cleared generated DriverKit and application products"
}

# ---------------------------------------------------------------------------
# Build app (from Scripts/build-dev.sh)
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
except (ValueError, plistlib.InvalidFileException):
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
except (ValueError, plistlib.InvalidFileException):
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
    echo "  1) Install profiles: ./Scripts/ojd signing install-profiles"
    echo "  2) Audit profiles:   ./Scripts/ojd signing audit"
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
    echo "  1) Install profiles: ./Scripts/ojd signing install-profiles"
    echo "  2) Audit profiles:   ./Scripts/ojd signing audit"
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
except (ValueError, plistlib.InvalidFileException):
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

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  ""|-h|--help|help)
    usage
    ;;
  build)
    case "$sub" in
      dev|release) build_app_bundle ;;
      dext) build_dext_bundle ;;
      *) die "Unknown: build $sub (expected: dev | release | dext)" ;;
    esac
    ;;
  *) die "Unknown command: $cmd" ;;
esac
