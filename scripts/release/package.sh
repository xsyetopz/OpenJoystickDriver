#!/usr/bin/env bash
# Release packaging helper for notarized app builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../platform/environment.sh"

usage() {
  cat <<'TXT'
Usage:
  OJD_ENV=release ./scripts/ojd package release [version]

Builds a release-signed app, embeds the DriverKit extension, submits it for
notarization, staples the accepted ticket, and writes:

  .build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg

This does not install the app, register a login item, or submit a sysext
activation request on the build machine.
TXT
}

cmd="${1:-}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  usage
  exit 0
fi

[[ "$cmd" == "release" ]] \
  || die "Unknown package command: ${cmd:-<empty>} (expected: release)"
[[ "$OJD_ENV" == "release" ]] || die "package $cmd requires OJD_ENV=release"

version="${1:-${GITHUB_REF_NAME:-$(date -u +%Y%m%d%H%M%S)}}"
safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
artifact_dir="$PROJECT_DIR/.build/release-artifacts"
app_path="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
notary_zip="$PROJECT_DIR/.build/OpenJoystickDriver-notarize.zip"
artifact_dmg="$artifact_dir/OpenJoystickDriver-${safe_version}-macOS.dmg"
staging_dir="$PROJECT_DIR/.build/dmg-staging"
rw_dmg="$PROJECT_DIR/.build/OpenJoystickDriver-${safe_version}-rw.dmg"
mount_dir="$PROJECT_DIR/.build/dmg-mount"
bundle_version_from_semver() {
  python3 - "$1" <<'PY'
import re
import sys

version = sys.argv[1]
match = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$", version)
if not match:
    print("ERROR: release tag must be SemVer without build metadata", file=sys.stderr)
    sys.exit(2)

major, minor, patch = (int(match.group(i)) for i in range(1, 4))
prerelease = match.group(4) or ""
build = major * 1_000_000 + minor * 1_000 + patch
if prerelease:
    numbers = [int(part) for part in re.findall(r"\d+", prerelease)]
    build = build * 100 + (numbers[-1] if numbers else 0)
else:
    build = build * 100 + 99
print(build)
PY
}

export OJD_BUNDLE_SHORT_VERSION="${OJD_BUNDLE_SHORT_VERSION:-$version}"
export OJD_BUNDLE_VERSION="${OJD_BUNDLE_VERSION:-$(bundle_version_from_semver "$version")}"

mount_dir_is_mounted() {
  /sbin/mount | /usr/bin/grep -F " on $1 " >/dev/null
}

detach_mount_dir_if_mounted() {
  local dir="$1"
  if [[ -d "$dir" ]] && mount_dir_is_mounted "$dir"; then
    /usr/bin/hdiutil detach "$dir" -quiet
  fi
}

cleanup_dmg_workdirs() {
  detach_mount_dir_if_mounted "$mount_dir"
  if mount_dir_is_mounted "$mount_dir"; then
    echo "WARNING: Refusing to remove active DMG mount path: $mount_dir" >&2
    return 0
  fi
  rm -rf "$staging_dir" "$rw_dmg" "$mount_dir"
}

mkdir -p "$artifact_dir"
trap cleanup_dmg_workdirs EXIT

echo "=== Build release app bundle ==="
OJD_ENV=release /usr/bin/env bash "$SCRIPT_DIR/../build-tools/build.sh" build release

echo ""
echo "=== Build and embed DriverKit extension ==="
OJD_ENV=release OJD_SKIP_INSTALL=1 /usr/bin/env bash "$SCRIPT_DIR/../build-tools/build.sh" build dext

[[ -d "$app_path" ]] || die "App bundle not found: $app_path"

echo ""
echo "=== Verify signed app before notarization ==="
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo ""
echo "=== Notarize and staple ==="
OJD_ENV=release \
  OJD_NOTARIZE_APP="$app_path" \
  OJD_NOTARIZE_ZIP="$notary_zip" \
  /usr/bin/env bash "$SCRIPT_DIR/notarize.sh" submit

echo ""
echo "=== Verify notarized app ==="
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"

echo ""
echo "=== Create drag-and-drop DMG ==="
detach_mount_dir_if_mounted "$mount_dir"
if mount_dir_is_mounted "$mount_dir"; then
  die "Mount path is still active; refusing to remove: $mount_dir"
fi
rm -rf "$staging_dir" "$mount_dir" "$rw_dmg" "$artifact_dmg"
mkdir -p "$staging_dir"
cp -R "$app_path" "$staging_dir/OpenJoystickDriver.app"
ln -s /Applications "$staging_dir/Applications"
/usr/bin/hdiutil create -srcfolder "$staging_dir" -volname "OpenJoystickDriver" -fs HFS+ -format UDZO "$artifact_dmg"
cleanup_dmg_workdirs
trap - EXIT
if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY:-}" != "-" ]]; then
  /usr/bin/codesign --sign "$CODESIGN_IDENTITY" --timestamp "$artifact_dmg"
  /usr/bin/codesign --verify --verbose=2 "$artifact_dmg"
else
  echo "WARNING: CODESIGN_IDENTITY not set; skipping DMG codesign." >&2
fi
/usr/bin/hdiutil verify "$artifact_dmg"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo ""
echo "Release artifact ready:"
echo "  $artifact_dmg"
