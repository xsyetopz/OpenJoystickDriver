#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }

repo_arg=()
apply=0
out_dir="$PROJECT_DIR/.build/github-actions-secrets"
developer_id_identity=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    --repo)
      [[ -n "${2:-}" ]] || die "Missing value for --repo"
      repo_arg=(--repo "$2")
      shift 2
      ;;
    --out)
      [[ -n "${2:-}" ]] || die "Missing value for --out"
      out_dir="$2"
      shift 2
      ;;
    --developer-id-identity)
      [[ -n "${2:-}" ]] || die "Missing value for --developer-id-identity"
      developer_id_identity="$2"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

read_secret() {
  local var="$1" prompt="$2"
  if [[ -n "${!var:-}" ]]; then
    printf '%s' "${!var}"
    return 0
  fi
  local value
  printf '%s: ' "$prompt" >&2
  IFS= read -r -s value
  printf '\n' >&2
  [[ -n "$value" ]] || die "$var cannot be empty"
  printf '%s' "$value"
}

base64_file() {
  local path="$1"
  python3 - "$path" <<'PY'
import base64, pathlib, sys
path = pathlib.Path(sys.argv[1]).expanduser()
sys.stdout.write(base64.b64encode(path.read_bytes()).decode("ascii"))
PY
}

write_secret_file() {
  local name="$1" value="$2"
  printf '%s' "$value" > "$values_dir/$name.txt"
}

display_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_DIR/"* ]]; then
    printf '%s' "${path#"$PROJECT_DIR/"}"
  else
    printf '%s' "$path"
  fi
}

gui_devid_profile="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile"
dext_profile="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile"

[[ -f "$gui_devid_profile" ]] || die "Missing GUI Developer ID profile: $gui_devid_profile"
[[ -f "$dext_profile" ]] || die "Missing DriverKit profile: $dext_profile"

certificate_secret="$(read_secret CERTIFICATE_SECRET 'identity export password')"
notarize_apple_id="$(read_secret NOTARIZE_APPLE_ID 'Apple ID email for notarization')"
notarize_password="$(read_secret NOTARIZE_PASSWORD 'Apple app-specific password for notarization')"
keychain_secret="${KEYCHAIN_SECRET:-$(openssl rand -base64 32 | tr -d '\n')}"

values_dir="$out_dir/values"
mkdir -p "$values_dir"
chmod 700 "$out_dir" "$values_dir"

[[ -n "$developer_id_identity" ]] || die "Pass --developer-id-identity with the Developer ID Application .p12 export"
[[ -f "$developer_id_identity" ]] || die "Missing Developer ID Application identity export: $developer_id_identity"

write_secret_file DEVELOPER_ID_APPLICATION_CERT_BASE64 "$(base64_file "$developer_id_identity")"
write_secret_file CERTIFICATE_SECRET "$certificate_secret"
write_secret_file KEYCHAIN_SECRET "$keychain_secret"
write_secret_file OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 "$(base64_file "$gui_devid_profile")"
write_secret_file OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64 "$(base64_file "$dext_profile")"
write_secret_file NOTARIZE_APPLE_ID "$notarize_apple_id"
write_secret_file NOTARIZE_PASSWORD "$notarize_password"
chmod 600 "$values_dir"/*.txt

cat > "$out_dir/apply-github-secrets.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_args=()
if [[ "${1:-}" == "--repo" ]]; then
  [[ -n "${2:-}" ]] || { echo "ERROR: Missing value for --repo" >&2; exit 2; }
  repo_args=(--repo "$2")
  shift 2
fi

gh auth status >/dev/null

for file in "$SCRIPT_DIR"/values/*.txt; do
  name="$(basename "$file" .txt)"
  echo "Setting $name"
  gh secret set "$name" ${repo_args[@]+"${repo_args[@]}"} < "$file"
done
SH
chmod 700 "$out_dir/apply-github-secrets.sh"

display_out_dir="$(display_path "$out_dir")"
display_apply_path="$(display_path "$out_dir/apply-github-secrets.sh")"

echo "Wrote GitHub Actions secret files:"
echo "  $display_out_dir"
echo ""
echo "Import with:"
if [[ "${#repo_arg[@]}" -gt 0 ]]; then
  echo "  ./$display_apply_path --repo ${repo_arg[1]}"
else
  echo "  ./$display_apply_path"
fi

if [[ "$apply" -eq 1 ]]; then
  "$out_dir/apply-github-secrets.sh" ${repo_arg[@]+"${repo_arg[@]}"}
fi
