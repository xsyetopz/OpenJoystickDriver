#!/usr/bin/env bash
# Signing helper for OpenJoystickDriver.
#
# Human-facing entrypoint:
#   ./scripts/ojd signing <subcommand>
#
# Default behavior (no args): generates `.env.dev` and `.env.release` in the project root.
#
# Goals:
# - No manual copy/paste of identities or Team IDs
# - Avoid heredoc pitfalls when pasting into wrapped terminals
# - Keep output non-sensitive (does not print identity strings)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }

cmd="${1:-configure}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  cat <<'TXT'
Usage:
  ./scripts/ojd signing install-profiles [~/Documents/Profiles]
  ./scripts/ojd signing ci-release-setup
  ./scripts/ojd signing configure
  ./scripts/ojd signing doctor
  ./scripts/ojd signing audit [paths...]
  ./scripts/ojd signing cert-info [--full] <cert.cer>
  ./scripts/ojd signing profile-info [--full] <profile1.provisionprofile> [profile2...]
  ./scripts/ojd signing import-embedded <profile.provisionprofile>
TXT
  exit 0
fi

cmd_install_profiles() {
  local SRC="${1:-}"
  if [[ -z "$SRC" ]]; then
    if [[ -d "$HOME/Documents/Profiles" ]]; then
      SRC="$HOME/Documents/Profiles"
    else
      SRC="$HOME/Documents/profiles"
    fi
  fi
  local DST="$HOME/Library/MobileDevice/Provisioning Profiles"
  [[ -d "$SRC" ]] || die "Source directory not found: $SRC (expected ~/Documents/Profiles)"
  mkdir -p "$DST"

  copy_one() {
    local name="$1"
    local src_path="$SRC/$name"
    [[ -f "$src_path" ]] || die "Missing profile: $src_path"
    cp -f "$src_path" "$DST/"
  }

  copy_one "OpenJoystickDriver.provisionprofile"
  copy_one "OpenJoystickDriver_DevID.provisionprofile"
  copy_one "OpenJoystickDriverDaemon.provisionprofile"
  copy_one "OpenJoystickDriverDaemon_DevID.provisionprofile"
  copy_one "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

  echo "Installed profiles to: $DST"
  ls -la "$DST" | awk '/OpenJoystickDriver/ {print "  " $9}'
}

cmd_ci_release_setup() {
  # Import release signing material from GitHub Actions secrets.
  #
  # CI entrypoint:
  #   ./scripts/ojd signing ci-release-setup
  #
  # Required environment variables:
  #   APPLE_DEVELOPMENT_CERT_BASE64
  #   DEVELOPER_ID_APPLICATION_CERT_BASE64
  #   CERTIFICATE_SECRET
  #   KEYCHAIN_SECRET
  #   RUNNER_TEMP
  #   OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64
  #   OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64
  #   OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64

  require_var() {
    local name="$1"
    [[ -n "${!name:-}" ]] || die "Missing required environment variable: $name"
  }

  write_base64_file() {
    local name="$1" out="$2"
    require_var "$name"
    printf '%s' "${!name}" | base64 --decode >"$out"
  }

  require_var APPLE_DEVELOPMENT_CERT_BASE64
  require_var DEVELOPER_ID_APPLICATION_CERT_BASE64
  require_var CERTIFICATE_SECRET
  require_var KEYCHAIN_SECRET
  require_var RUNNER_TEMP
  require_var OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64
  require_var OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64
  require_var OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64

  local keychain_path="$RUNNER_TEMP/openjoystickdriver-release.keychain-db"
  local profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  local payload_dir="$RUNNER_TEMP/openjoystickdriver-release-payloads"

  mkdir -p "$profiles_dir" "$payload_dir"

  echo "Creating temporary signing keychain..."
  security create-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
  security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"

  local apple_dev_payload="$payload_dir/apple-development-cert.blob"
  local developer_id_payload="$payload_dir/developer-id-application-cert.blob"
  write_base64_file APPLE_DEVELOPMENT_CERT_BASE64 "$apple_dev_payload"
  write_base64_file DEVELOPER_ID_APPLICATION_CERT_BASE64 "$developer_id_payload"

  echo "Importing signing certificates..."
  security import "$apple_dev_payload" -f pkcs12 -k "$keychain_path" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
  security import "$developer_id_payload" -f pkcs12 -k "$keychain_path" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$keychain_path"

  echo "Installing provisioning profiles..."
  write_base64_file OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_DevID.provisionprofile"
  write_base64_file OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriverDaemon_DevID.provisionprofile"
  write_base64_file OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

  echo "Generating release signing environment..."
  (
    cd "$PROJECT_DIR"
    GUI_DEV_PROFILE="$profiles_dir/OpenJoystickDriver_DevID.provisionprofile" \
      DAEMON_DEV_PROFILE="$profiles_dir/OpenJoystickDriverDaemon_DevID.provisionprofile" \
      ./scripts/ojd signing configure
  )

  local release_env_file="$PROJECT_DIR/.env.release"
  if [[ ! -f "$release_env_file" ]] \
    || ! grep -q '^CODESIGN_IDENTITY=' "$release_env_file" \
    || ! grep -q '^GUI_CODESIGN_IDENTITY=' "$release_env_file" \
    || ! grep -q '^DAEMON_CODESIGN_IDENTITY=' "$release_env_file"; then
    die "Release signing is not configured; fix the certificate/profile mismatch reported above."
  fi

  echo "Release signing setup complete."
  echo "Safe identity summary:"
  security find-identity -v -p codesigning "$keychain_path" | awk '/Apple Development:|Developer ID Application:/ {print "  " $2}'
}

cmd_audit() {
  decode_profile() {
    local profile="$1"
    if security cms -D -i "$profile" 2>/dev/null; then
      return 0
    fi
    openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null
  }

  collect_profiles() {
    if [[ $# -gt 0 ]]; then
      printf '%s\n' "$@"
      return 0
    fi

    local found=0
    for d in "$HOME/Documents/profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
      if [[ -d "$d" ]]; then
        found=1
        find "$d" -maxdepth 1 -type f \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) -print 2>/dev/null || true
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo "No profile directories found under:" 1>&2
      echo "  - $HOME/Documents/profiles" 1>&2
      echo "  - $HOME/Library/MobileDevice/Provisioning Profiles" 1>&2
    fi
  }

  audit_one() {
    local profile="$1"
    python3 - "$profile" <<'PY'
import os, sys, plistlib, subprocess, tempfile
profile = sys.argv[1]
def decode_profile(path: str) -> bytes:
    p = subprocess.run(['bash','-lc', f'decode_profile {path!r}'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError("decode failed")
    return p.stdout
def classify_cert_kind(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(prefix='ojd_cert_', suffix='.der', delete=True) as tf:
        tf.write(der); tf.flush()
        p = subprocess.run(['openssl','x509','-inform','DER','-in',tf.name,'-noout','-subject'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode != 0:
            return "UNKNOWN"
        subj = p.stdout.decode('utf-8','replace')
        if 'CN=' not in subj:
            return "UNKNOWN"
        cn = subj.split('CN=',1)[1].split('\n',1)[0]
        cn = cn.split('/',1)[0].strip()
        return cn.split(':',1)[0] if ':' in cn else cn
try:
    plist_bytes = decode_profile(profile)
    obj = plistlib.loads(plist_bytes)
except Exception:
    print(f"==> {os.path.basename(profile)}")
    print("  decode_ok: false")
    sys.exit(0)
ent = obj.get('Entitlements', {}) or {}
app_id = ent.get('com.apple.application-identifier') or ent.get('application-identifier')
bundle_suffix = "UNKNOWN"
if isinstance(app_id, str) and '.' in app_id:
    bundle_suffix = app_id.split('.', 1)[1]
certs = obj.get('DeveloperCertificates') or []
cert_kind = "UNKNOWN"
if certs and isinstance(certs[0], (bytes, bytearray)):
    cert_kind = classify_cert_kind(certs[0])
has_hid_virtual = 'com.apple.developer.hid.virtual.device' in ent
print(f"==> {os.path.basename(profile)}")
print("  decode_ok: true")
print(f"  bundle_id_suffix: {bundle_suffix}")
print(f"  developer_certificate_kind: {cert_kind}")
print(f"  has_entitlement_hid_virtual_device: {has_hid_virtual}")
PY
  }

  export -f decode_profile
  local profiles
  profiles=$(collect_profiles "$@") || true
  [[ -n "${profiles:-}" ]] || return 0
  while IFS= read -r p; do
    [[ -n "$p" && -f "$p" ]] || continue
    audit_one "$p"
  done <<< "$profiles"
}

cmd_cert_info() {
  local full=0
  if [[ "${1:-}" == "--full" ]]; then
    full=1
    shift
  fi
  [[ $# -eq 1 ]] || die "Usage: ./scripts/ojd signing cert-info [--full] <cert.cer>"
  local cert="$1"
  [[ -f "$cert" ]] || die "Missing file: $cert"
  python3 - "$full" "$cert" <<'PY'
import sys, subprocess
full = int(sys.argv[1]); path = sys.argv[2]
def short(s: str) -> str:
    return s if len(s) <= 12 else (s[:8] + "…" + s[-4:])
serial = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-serial"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip().split("=", 1)[1]
fp = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-fingerprint","-sha1"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip().split("=", 1)[1].replace(":", "").lower()
subj = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-subject","-nameopt","RFC2253"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip()
ou = subj.split("OU=", 1)[1].split(",", 1)[0] if "OU=" in subj else ""
cn = subj.split("CN=", 1)[1].split(",", 1)[0] if "CN=" in subj else ""
cn_suffix = "NONE"
if cn.endswith(")") and "(" in cn:
    cn_suffix = cn.rsplit("(", 1)[1].rstrip(")")
print(f"path: {path}")
if full:
    print(f"sha1: {fp}")
    print(f"serial: {serial}")
else:
    print(f"sha1: {short(fp)}  (use --full for full)")
    print(f"serial: {short(serial)}  (use --full for full)")
print(f"ou: {ou}")
print(f"cn_suffix: {cn_suffix}")
PY
}

cmd_profile_info() {
  local full=0
  if [[ "${1:-}" == "--full" ]]; then
    full=1
    shift
  fi
  [[ $# -ge 1 ]] || die "Usage: ./scripts/ojd signing profile-info [--full] <profile1> [profile2...]"
  python3 - "$full" "$@" <<'PY'
import os, sys, plistlib, subprocess, tempfile
full = int(sys.argv[1])
profiles = sys.argv[2:]
def decode_profile(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if (p.returncode == 0 and p.stdout) else b""
def sha1_of_der(der: bytes) -> str:
    out = subprocess.run(["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"], input=der,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout.decode().strip()
    return out.split("=", 1)[1].replace(":", "").lower()
def serial_of_der(der: bytes) -> str:
    out = subprocess.run(["openssl","x509","-inform","DER","-noout","-serial"], input=der,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout.decode().strip()
    return out.split("=", 1)[1]
def subject_rfc2253_of_der(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der); tmp = f.name
    try:
        return subprocess.run(["openssl","x509","-inform","DER","-in",tmp,"-noout","-subject","-nameopt","RFC2253"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip()
    finally:
        try: os.unlink(tmp)
        except OSError: pass
def short(s: str) -> str:
    return s if len(s) <= 12 else (s[:8] + "…" + s[-4:])
for path in profiles:
    path = os.path.expanduser(path)
    base = os.path.basename(path)
    print(f"==> {base}")
    if not os.path.isfile(path):
        print("  error: missing file")
        continue
    try:
        raw = decode_profile(path)
        if not raw or b"<?xml" not in raw:
            raise RuntimeError("decode failed")
        raw = raw[raw.index(b"<?xml") :]
        obj = plistlib.loads(raw)
    except Exception:
        print("  error: could not decode profile")
        continue
    name = obj.get("Name") if isinstance(obj.get("Name"), str) else "UNKNOWN"
    ti = obj.get("TeamIdentifier") or []
    team = ti[0] if isinstance(ti, list) and ti and isinstance(ti[0], str) else "UNKNOWN"
    print(f"  name: {name}")
    print(f"  team_identifier: {team}")
    certs = obj.get("DeveloperCertificates") or []
    if not certs or not isinstance(certs[0], (bytes, bytearray)):
        print("  embedded_cert: missing")
        continue
    der = certs[0]
    sha1 = sha1_of_der(der)
    serial = serial_of_der(der)
    subj = subject_rfc2253_of_der(der)
    ou = subj.split("OU=", 1)[1].split(",", 1)[0] if "OU=" in subj else ""
    cn = subj.split("CN=", 1)[1].split(",", 1)[0] if "CN=" in subj else ""
    cn_suffix = "NONE"
    if cn.endswith(")") and "(" in cn:
        cn_suffix = cn.rsplit("(", 1)[1].rstrip(")")
    if full:
        print(f"  embedded_cert_sha1: {sha1}")
        print(f"  embedded_cert_serial: {serial}")
    else:
        print(f"  embedded_cert_sha1: {short(sha1)}  (use --full for full)")
        print(f"  embedded_cert_serial: {short(serial)}  (use --full for full)")
    print(f"  embedded_cert_ou: {ou}")
    print(f"  embedded_cert_cn_suffix: {cn_suffix}")
PY
}

cmd_import_embedded() {
  local profile="${1:-}"
  [[ -n "$profile" ]] || die "Usage: ./scripts/ojd signing import-embedded <profile.provisionprofile>"
  [[ -f "$profile" ]] || die "Missing profile file: $profile"
  local tmp="/tmp/ojd-embedded-devcert.der"
  python3 - "$profile" "$tmp" <<'PY'
import os, sys, plistlib, subprocess
profile = os.path.expanduser(sys.argv[1]); out_path = sys.argv[2]
def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if (p.returncode == 0 and p.stdout) else b""
raw = decode(profile)
if not raw or b"<?xml" not in raw:
    raise SystemExit("ERROR: could not decode provisioning profile")
raw = raw[raw.index(b"<?xml") :]
obj = plistlib.loads(raw)
certs = obj.get("DeveloperCertificates") or []
if not certs or not isinstance(certs[0], (bytes, bytearray)):
    raise SystemExit("ERROR: profile has no DeveloperCertificates[0]")
with open(out_path, "wb") as f:
    f.write(certs[0])
PY
  echo "Extracted embedded certificate to: $tmp"
  echo "Importing into login keychain (Keychain may prompt)…"
  security import "$tmp" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
  echo "Done."
  echo "Now run:"
  echo "  security find-identity -v -p codesigning"
}

cmd_doctor() {
  # Reuse our own audit/profile-info helpers to keep output safe.
  echo "OpenJoystickDriver signing doctor"
  echo ""
  echo "1) Keychain identities:"
  security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print "  Apple Development SHA1: " tolower($2)} /Developer ID Application:/{print "  Developer ID App SHA1:  " tolower($2)}' || true
  echo ""
  echo "2) Profiles audit:"
  cmd_audit
  echo ""
  echo "3) Release signing match:"
  set +e
  python3 - <<'PY'
import os, plistlib, subprocess, sys

profiles_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
gui = os.path.join(profiles_dir, "OpenJoystickDriver_DevID.provisionprofile")
daemon = os.path.join(profiles_dir, "OpenJoystickDriverDaemon_DevID.provisionprofile")

def decode_profile(path: str) -> bytes:
    p = subprocess.run(["security", "cms", "-D", "-i", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if p.returncode == 0 and p.stdout else b""

def profile_sha1(path: str) -> str:
    raw = decode_profile(path)
    if not raw or b"<?xml" not in raw:
        raise RuntimeError(f"could not decode {path}")
    raw = raw[raw.index(b"<?xml"):]
    obj = plistlib.loads(raw)
    certs = obj.get("DeveloperCertificates") or []
    if not certs:
        raise RuntimeError(f"missing DeveloperCertificates in {path}")
    p = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-fingerprint", "-sha1"],
        input=certs[0], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    return p.stdout.decode().strip().split("=", 1)[1].replace(":", "").lower()

def developer_id_identities() -> set[str]:
    p = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    found: set[str] = set()
    for line in p.stdout.splitlines():
        if '"Developer ID Application:' not in line:
            continue
        parts = line.split()
        if len(parts) >= 2 and len(parts[1]) == 40:
            found.add(parts[1].lower())
    return found

try:
    gui_sha = profile_sha1(gui)
    daemon_sha = profile_sha1(daemon)
except Exception as e:
    print(f"  [FAIL] {e}")
    sys.exit(1)

ids = developer_id_identities()
print(f"  GUI DevID profile cert:    {gui_sha}")
print(f"  daemon DevID profile cert: {daemon_sha}")
print(f"  keychain Developer IDs:    {', '.join(sorted(ids)) if ids else 'none'}")

missing = [sha for sha in [gui_sha, daemon_sha] if sha not in ids]
if missing:
    print("  [FAIL] one or more Developer ID profile certificates are not available as signing identities in Keychain.")
    print("  Need: a Developer ID Application signing identity whose SHA1 matches each profile's embedded certificate.")
    print("  Note: matching Team ID is necessary, but not enough; codesign also needs the matching certificate private key.")
    print("  Fix: install the missing Developer ID Application certificate/private key, or regenerate that profile for an installed Developer ID identity.")
    sys.exit(1)

if gui_sha != daemon_sha:
    print("  [OK] GUI and daemon profiles use different Developer ID certs, and both are installed signing identities.")
else:
    print("  [OK] release Developer ID profiles match an installed signing identity")
PY
  local release_status=$?
  set -e
  echo ""
  if [[ "$release_status" -eq 0 ]]; then
    echo "Next:"
    echo "  ./scripts/ojd signing configure"
    echo "  ./scripts/ojd build release"
    echo "  ./scripts/ojd notarize submit"
  else
    echo "STATUS BLOCKED"
    echo "Release signing/notarization cannot be proven until the missing Developer ID signing identity above is fixed."
    echo ""
    echo "Resolution:"
    echo "  Option A: install/import the Developer ID Application certificate + private key whose SHA1 matches the daemon profile."
    echo "  Option B: regenerate OpenJoystickDriverDaemon_DevID.provisionprofile and select an installed Developer ID Application identity."
    echo "  In both options, ensure com.apple.developer.hid.virtual.device is present."
    echo "  Then install profiles: ./scripts/ojd signing install-profiles \"$HOME/Documents/Profiles\""
    echo "  Then re-run: ./scripts/ojd signing doctor"
    return "$release_status"
  fi
}

case "$cmd" in
  install-profiles) cmd_install_profiles "${1:-}"; exit 0 ;;
  ci-release-setup) cmd_ci_release_setup; exit 0 ;;
  audit) cmd_audit "$@"; exit 0 ;;
  cert-info) cmd_cert_info "$@"; exit 0 ;;
  profile-info) cmd_profile_info "$@"; exit 0 ;;
  import-embedded) cmd_import_embedded "$@"; exit 0 ;;
  doctor) cmd_doctor; exit 0 ;;
  configure) ;; # continue into original implementation
  *) die "Unknown signing command: $cmd" ;;
esac

DEV_ENV="${DEV_ENV:-$PROJECT_DIR/.env.dev}"
REL_ENV="${REL_ENV:-$PROJECT_DIR/.env.release}"

GUI_DEV_PROFILE="${GUI_DEV_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"
GUI_DEVID_PROFILE="${GUI_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
DAEMON_DEV_PROFILE="${DAEMON_DEV_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile}"
DAEMON_DEVID_PROFILE="${DAEMON_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile}"
DEXT_PROFILE="${DEXT_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
APPLE_DEV_IDENTITY="${APPLE_DEV_IDENTITY:-}"
DEVID_APP_IDENTITY="${DEVID_APP_IDENTITY:-}"

usage() {
  cat <<'TXT'
Usage:
  ./scripts/ojd signing configure

Reads:
  - Keychain code signing identities (Apple Development + Developer ID Application)
  - Provisioning profiles from ~/Library/MobileDevice/Provisioning Profiles/

Writes:
  - .env.dev
  - .env.release

Environment overrides (optional):
  GUI_DEV_PROFILE, GUI_DEVID_PROFILE, DAEMON_DEV_PROFILE, DAEMON_DEVID_PROFILE, DEXT_PROFILE
  APPLE_DEV_IDENTITY, DEVID_APP_IDENTITY
TXT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

export PROJECT_DIR
export SCRIPT_DIR
export DEV_ENV
export REL_ENV
export GUI_DEV_PROFILE
export GUI_DEVID_PROFILE
export DAEMON_DEV_PROFILE
export DAEMON_DEVID_PROFILE
export DEXT_PROFILE
export APPLE_DEV_IDENTITY
export DEVID_APP_IDENTITY

python3 "$SCRIPT_DIR/configure.py"

