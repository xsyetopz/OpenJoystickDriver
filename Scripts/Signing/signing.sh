#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }

cmd="${1:-configure}"
shift || true

signing_mode() {
  case "$1" in
    all|development|release) printf '%s\n' "$1" ;;
    *) die "--mode must be all, development or release (got: $1)" ;;
  esac
}

cmd_install_profiles() {
  local mode=all SRC=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        [[ $# -ge 2 ]] || die "--mode requires a value"
        mode="$(signing_mode "$2")"
        shift 2
        ;;
      -*) die "Unknown install-profiles option: $1" ;;
      *)
        [[ -z "$SRC" ]] || die "install-profiles accepts one source directory"
        SRC="$1"
        shift
        ;;
    esac
  done
  local DST="$HOME/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "$DST"
  local installed=()
  local search_dirs=()
  if [[ -n "$SRC" ]]; then
    [[ -d "$SRC" ]] || die "Source directory not found: $SRC"
    search_dirs+=("$SRC")
  else
    search_dirs+=(
      "$HOME/Documents/Profiles"
      "$HOME/Documents/profiles"
      "$HOME/Downloads/Profiles"
      "$HOME/Downloads/profiles"
      "$HOME/Downloads"
      "$DST"
    )
  fi

  copy_one() {
    local name="$1" required="$2"
    local directory src_path=""
    for directory in "${search_dirs[@]}"; do
      if [[ -f "$directory/$name" ]]; then
        src_path="$directory/$name"
        break
      fi
    done
    if [[ -z "$src_path" ]]; then
      if [[ "$required" == "1" ]]; then
        echo "ERROR: Missing Apple provisioning profile: $name" >&2
        if [[ -t 0 && -z "${CI:-}" ]]; then
          open "https://developer.apple.com/account/resources/profiles/list" >/dev/null 2>&1 || true
          echo "Opened the Apple Developer provisioning profiles page." >&2
        fi
        echo "Download $name, then re-run the original command." >&2
        return 2
      fi
      echo "Skipping optional profile: $name"
      return 0
    fi
    if [[ "$src_path" != "$DST/$name" ]]; then
      cp -f "$src_path" "$DST/"
    fi
    installed+=("$name")
  }

  if [[ "$mode" != "release" ]]; then
    copy_one "OpenJoystickDriver.provisionprofile" 1
    copy_one "OpenJoystickDriver_XboxUSBDevice.provisionprofile" 1
  fi
  copy_one "OpenJoystickDriver_DevID.provisionprofile" "$([[ "$mode" == "release" ]] && echo 1 || echo 0)"
  copy_one "OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile" "$([[ "$mode" == "release" ]] && echo 1 || echo 0)"

  echo "Installed profiles to: $DST"
  printf '  %s\n' "${installed[@]}"
}

cmd_ci_release_setup() {

  require_var() {
    local name="$1"
    [[ -n "${!name:-}" ]] || die "Missing required environment variable: $name"
  }

  write_base64_file() {
    local name="$1" out="$2"
    require_var "$name"
    printf '%s' "${!name}" | base64 --decode >"$out"
  }

  require_var DEVELOPER_ID_APPLICATION_CERT_BASE64
  require_var CERTIFICATE_SECRET
  require_var KEYCHAIN_SECRET
  require_var RUNNER_TEMP
  require_var OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64
  require_var OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64

  local keychain_path="$RUNNER_TEMP/openjoystickdriver-release.keychain-db"
  local profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  local payload_dir="$RUNNER_TEMP/openjoystickdriver-release-payloads"

  mkdir -p "$profiles_dir" "$payload_dir"

  echo "Creating temporary signing keychain..."
  security create-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
  security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"

  local developer_id_payload="$payload_dir/developer-id-application-cert.blob"
  write_base64_file DEVELOPER_ID_APPLICATION_CERT_BASE64 "$developer_id_payload"

  echo "Importing release signing certificate..."
  security import "$developer_id_payload" -f pkcs12 -k "$keychain_path" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$keychain_path"

  echo "Installing provisioning profiles..."
  write_base64_file OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_DevID.provisionprofile"
  write_base64_file OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile"

  echo "Generating release signing environment..."
  (
    cd "$PROJECT_DIR"
    just signing-configure --mode release
  )

  local release_env_file="$PROJECT_DIR/.env.release"
  if [[ ! -f "$release_env_file" ]] \
    || ! grep -q '^CODESIGN_IDENTITY=' "$release_env_file"; then
    die "Release signing is not configured; fix the certificate/profile mismatch reported above."
  fi

  echo "Release signing setup complete."
  echo "Safe identity summary:"
  security find-identity -v -p codesigning "$keychain_path" | awk '/Developer ID Application:/ {print "  " $2}'
}

cmd_audit() {
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
    for command in (
        ["security", "cms", "-D", "-i", path],
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
    ):
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0 and result.stdout:
            return result.stdout
    raise RuntimeError("decode failed")
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
except (RuntimeError, plistlib.InvalidFileException):
    print(f"==> {os.path.basename(profile)}")
    print("  decode_ok: false")
    sys.exit(0)
ent = obj.get('Entitlements', {}) or {}
app_id = ent.get('com.apple.application-identifier') or ent.get('application-identifier')
bundle_suffix = "UNKNOWN"
if isinstance(app_id, str) and '.' in app_id:
    bundle_suffix = app_id.split('.', 1)[1]
certs = obj.get('DeveloperCertificates') or []
cert_kinds = [classify_cert_kind(c) for c in certs if isinstance(c, (bytes, bytearray))]
cert_kind = ",".join(cert_kinds) if cert_kinds else "UNKNOWN"
has_hid_virtual = 'com.apple.developer.hid.virtual.device' in ent
print(f"==> {os.path.basename(profile)}")
print("  decode_ok: true")
print(f"  bundle_id_suffix: {bundle_suffix}")
print(f"  developer_certificate_kind: {cert_kind}")
print(f"  has_entitlement_hid_virtual_device: {has_hid_virtual}")
PY
  }

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
  [[ $# -eq 1 ]] || die "Usage: just signing-cert-info [--full] <cert.cer>"
  local cert="$1"
  [[ -f "$cert" ]] || die "Missing file: $cert"
  python3 - "$full" "$cert" <<'PY'
import sys, subprocess
full = int(sys.argv[1]); path = sys.argv[2]
def short(s: str) -> str:
    return s if len(s) <= 12 else (s[:8] + "..." + s[-4:])
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
  [[ $# -ge 1 ]] || die "Usage: just signing-profile-info [--full] <profile1> [profile2...]"
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
    return s if len(s) <= 12 else (s[:8] + "..." + s[-4:])
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
    except (RuntimeError, ValueError, plistlib.InvalidFileException):
        print("  error: could not decode profile")
        continue
    name = obj.get("Name") if isinstance(obj.get("Name"), str) else "UNKNOWN"
    ti = obj.get("TeamIdentifier") or []
    team = ti[0] if isinstance(ti, list) and ti and isinstance(ti[0], str) else "UNKNOWN"
    print(f"  name: {name}")
    print(f"  team_identifier: {team}")
    certs = obj.get("DeveloperCertificates") or []
    ders = [c for c in certs if isinstance(c, (bytes, bytearray))]
    if not ders:
        print("  embedded_cert: missing")
        continue
    print(f"  embedded_cert_count: {len(ders)}")
    for index, der in enumerate(ders):
        sha1 = sha1_of_der(der)
        serial = serial_of_der(der)
        subj = subject_rfc2253_of_der(der)
        ou = subj.split("OU=", 1)[1].split(",", 1)[0] if "OU=" in subj else ""
        cn = subj.split("CN=", 1)[1].split(",", 1)[0] if "CN=" in subj else ""
        cn_suffix = "NONE"
        if cn.endswith(")") and "(" in cn:
            cn_suffix = cn.rsplit("(", 1)[1].rstrip(")")
        if full:
            print(f"  embedded_cert[{index}]_sha1: {sha1}")
            print(f"  embedded_cert[{index}]_serial: {serial}")
        else:
            print(f"  embedded_cert[{index}]_sha1: {short(sha1)}  (use --full for full)")
            print(f"  embedded_cert[{index}]_serial: {short(serial)}  (use --full for full)")
        print(f"  embedded_cert[{index}]_ou: {ou}")
        print(f"  embedded_cert[{index}]_cn_suffix: {cn_suffix}")
PY
}

# Runs in a subshell so the EXIT trap still sees the local $tmpdir.
cmd_import_embedded() (
  local profile="${1:-}"
  [[ -n "$profile" ]] || die "Usage: just signing-import-embedded <profile.provisionprofile>"
  [[ -f "$profile" ]] || die "Missing profile file: $profile"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  python3 - "$profile" "$tmpdir" <<'PY'
import os, sys, plistlib, subprocess
profile = os.path.expanduser(sys.argv[1]); out_dir = sys.argv[2]
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
certs = [c for c in (obj.get("DeveloperCertificates") or []) if isinstance(c, (bytes, bytearray))]
if not certs:
    raise SystemExit("ERROR: profile has no DeveloperCertificates")
for index, cert in enumerate(certs):
    with open(os.path.join(out_dir, f"cert-{index}.der"), "wb") as f:
        f.write(cert)
PY
  echo "Importing every embedded certificate into the login keychain (Keychain may prompt)..."
  local der sha1
  for der in "$tmpdir"/cert-*.der; do
    sha1=$(openssl x509 -inform DER -in "$der" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
    echo "  importing $(basename "$der" .der) sha1=$sha1"
    security import "$der" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
  done
  echo "Done."
  echo "Now run:"
  echo "  security find-identity -v -p codesigning"
)

case "$cmd" in
  install-profiles) cmd_install_profiles "$@"; exit 0 ;;
  ci-release-setup) cmd_ci_release_setup; exit 0 ;;
  audit) cmd_audit "$@"; exit 0 ;;
  cert-info) cmd_cert_info "$@"; exit 0 ;;
  profile-info) cmd_profile_info "$@"; exit 0 ;;
  import-embedded) cmd_import_embedded "$@"; exit 0 ;;
  configure) ;; # handled below
  *) die "Unknown signing command: $cmd" ;;
esac

python3 "$SCRIPT_DIR/configure.py" --project-dir "$PROJECT_DIR" "$@"
