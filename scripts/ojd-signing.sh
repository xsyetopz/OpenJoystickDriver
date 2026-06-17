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
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

cmd="${1:-configure}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  cat << 'TXT'
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

source "$SCRIPT_DIR/ojd-signing-commands.sh"

case "$cmd" in
  install-profiles)
    cmd_install_profiles "${1:-}"
    exit 0
    ;;
  ci-release-setup)
    cmd_ci_release_setup
    exit 0
    ;;
  audit)
    cmd_audit "$@"
    exit 0
    ;;
  cert-info)
    cmd_cert_info "$@"
    exit 0
    ;;
  profile-info)
    cmd_profile_info "$@"
    exit 0
    ;;
  import-embedded)
    cmd_import_embedded "$@"
    exit 0
    ;;
  doctor)
    cmd_doctor
    exit 0
    ;;
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
  cat << 'TXT'
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

python3 "$SCRIPT_DIR/ojd-signing-configure.py"
