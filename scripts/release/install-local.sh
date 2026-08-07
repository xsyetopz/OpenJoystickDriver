#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../platform/environment.sh"
VERSION="${1:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}"
APP_SOURCE="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
APP_DESTINATION="/Applications/OpenJoystickDriver.app"
APP_STAGED="/Applications/.OpenJoystickDriver.app.staged.$$"
APP_BACKUP="/Applications/.OpenJoystickDriver.app.backup.$$"

cleanup() {
  rm -rf "$APP_STAGED"
  if [[ -d "$APP_BACKUP" && ! -d "$APP_DESTINATION" ]]; then
    mv "$APP_BACKUP" "$APP_DESTINATION"
  else
    rm -rf "$APP_BACKUP"
  fi
}
trap cleanup EXIT

OJD_ENV=release /usr/bin/env bash "$SCRIPT_DIR/package.sh" release "$VERSION"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "ERROR: Release package did not produce $APP_SOURCE" >&2
  exit 1
fi

/usr/bin/ditto "$APP_SOURCE" "$APP_STAGED"
/usr/bin/codesign --verify --deep --strict "$APP_STAGED"
if [[ -d "$APP_DESTINATION" ]]; then mv "$APP_DESTINATION" "$APP_BACKUP"; fi
mv "$APP_STAGED" "$APP_DESTINATION"
/usr/bin/codesign --verify --deep --strict "$APP_DESTINATION"
rm -rf "$APP_BACKUP"
trap - EXIT
printf 'Installed OpenJoystickDriver %s at %s\n' "$VERSION" "$APP_DESTINATION"
