# Code signing: provisioning profiles, the .env.* signing settings, and the release secrets.
# Profile and certificate facts print shortened hashes unless --full is given.

signing_facts := "python3 Scripts/Signing/profile_certs.py"
profiles_dir := "$HOME/Library/MobileDevice/Provisioning Profiles"

# Copy provisioning profiles into MobileDevice from a folder, or from ~/Documents/Profiles and ~/Downloads; --mode all, development or release.
[positional-arguments]
signing-install-profiles *args:
    #!/usr/bin/env bash
    set -euo pipefail
    die() { echo "ERROR: $*" >&2; exit 2; }
    mode=all source=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --mode)
          [[ $# -ge 2 ]] || die "--mode requires a value"
          case "$2" in all|development|release) mode="$2" ;; *) die "--mode must be all, development or release (got: $2)" ;; esac
          shift 2
          ;;
        -*) die "Unknown signing-install-profiles option: $1" ;;
        *)
          [[ -z "$source" ]] || die "signing-install-profiles accepts one source directory"
          source="$1"
          shift
          ;;
      esac
    done
    destination="{{ profiles_dir }}"
    mkdir -p "$destination"
    if [[ -n "$source" ]]; then
      [[ -d "$source" ]] || die "Source directory not found: $source"
      search=("$source")
    else
      search=("$HOME/Documents/Profiles" "$HOME/Documents/profiles" "$HOME/Downloads/Profiles"
        "$HOME/Downloads/profiles" "$HOME/Downloads" "$destination")
    fi
    installed=()
    copy_one() {
      local name="$1" required="$2" directory found=""
      for directory in "${search[@]}"; do
        if [[ -f "$directory/$name" ]]; then found="$directory/$name"; break; fi
      done
      if [[ -z "$found" ]]; then
        [[ "$required" == 1 ]] || { echo "Skipping optional profile: $name"; return 0; }
        echo "ERROR: Missing Apple provisioning profile: $name" >&2
        if [[ -t 0 && -z "${CI:-}" ]]; then
          open "https://developer.apple.com/account/resources/profiles/list" >/dev/null 2>&1 || true
          echo "Opened the Apple Developer provisioning profiles page." >&2
        fi
        echo "Download $name, then re-run the original command." >&2
        return 2
      fi
      [[ "$found" == "$destination/$name" ]] || cp -f "$found" "$destination/"
      installed+=("$name")
    }
    release_required=$([[ "$mode" == release ]] && echo 1 || echo 0)
    if [[ "$mode" != release ]]; then
      copy_one OpenJoystickDriver.provisionprofile 1
      copy_one OpenJoystickDriver_XboxUSBDevice.provisionprofile 1
    fi
    copy_one OpenJoystickDriver_DevID.provisionprofile "$release_required"
    copy_one OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile "$release_required"
    echo "Installed profiles to: $destination"
    printf '  %s\n' "${installed[@]}"

# Write .env.dev and .env.release from the Keychain and the profiles.
[positional-arguments]
signing-configure *args:
    python3 Scripts/Signing/configure.py --project-dir "$PWD" "$@"

# Audit provisioning profiles without printing identifiers.
[positional-arguments]
signing-audit *paths:
    {{ signing_facts }} audit "$@"

# Show the Team ID and subject of a .cer file; --full prints the whole hashes.
[positional-arguments]
signing-cert-info *args:
    {{ signing_facts }} cert-info "$@"

# Show the certificates embedded in provisioning profiles; --full prints the whole hashes.
[positional-arguments]
signing-profile-info *args:
    {{ signing_facts }} profile-info "$@"

# Import every certificate embedded in a profile into the login Keychain.
signing-import-embedded profile:
    #!/usr/bin/env bash
    set -euo pipefail
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    {{ signing_facts }} extract-certs {{ quote(profile) }} "$work"
    echo "Importing every embedded certificate into the login keychain (Keychain may prompt)..."
    for der in "$work"/cert-*.der; do
      sha1=$(openssl x509 -inform DER -in "$der" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
      echo "  importing $(basename "$der" .der) sha1=$sha1"
      security import "$der" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
    done
    echo "Done. Next, run: security find-identity -v -p codesigning"

# Import the GitHub Actions release secrets into a temporary keychain (CI only).
signing-ci-release-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    die() { echo "ERROR: $*" >&2; exit 2; }
    for name in DEVELOPER_ID_APPLICATION_CERT_BASE64 CERTIFICATE_SECRET KEYCHAIN_SECRET RUNNER_TEMP \
      OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64; do
      [[ -n "${!name:-}" ]] || die "Missing required environment variable: $name"
    done
    keychain="$RUNNER_TEMP/openjoystickdriver-release.keychain-db"
    profiles="{{ profiles_dir }}"
    payloads="$RUNNER_TEMP/openjoystickdriver-release-payloads"
    mkdir -p "$profiles" "$payloads"
    echo "Creating temporary signing keychain..."
    security create-keychain -p "$KEYCHAIN_SECRET" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain"
    security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
    certificate="$payloads/developer-id-application-cert.blob"
    printf '%s' "$DEVELOPER_ID_APPLICATION_CERT_BASE64" | base64 --decode >"$certificate"
    echo "Importing release signing certificate..."
    security import "$certificate" -f pkcs12 -k "$keychain" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$keychain"
    echo "Installing provisioning profiles..."
    printf '%s' "$OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64" | base64 --decode >"$profiles/OpenJoystickDriver_DevID.provisionprofile"
    printf '%s' "$OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64" | base64 --decode >"$profiles/OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile"
    echo "Generating release signing environment..."
    just signing-configure --mode release
    grep -q '^CODESIGN_IDENTITY=' .env.release 2>/dev/null \
      || die "Release signing is not configured; fix the certificate/profile mismatch reported above."
    echo "Release signing setup complete."
    echo "Safe identity summary:"
    security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application:/ {print "  " $2}'

# Write or import the GitHub Actions release secrets.
[positional-arguments]
signing-export-github-secrets *args:
    Scripts/Signing/export-github-secrets.sh "$@"
