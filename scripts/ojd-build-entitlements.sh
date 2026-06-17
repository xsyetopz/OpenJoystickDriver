#!/usr/bin/env bash
# Entitlement inspection helpers for ojd-build.sh.

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

