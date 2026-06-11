#!/usr/bin/env bash
# Release packaging helper for notarized app builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

die() { echo "ERROR: $*" >&2; exit 2; }

usage() {
  cat <<'TXT'
Usage:
  OJD_ENV=release ./scripts/ojd package release [version]
  OJD_ENV=release ./scripts/ojd package appcast [version]

Builds a release-signed app, embeds the DriverKit extension, submits it for
notarization, staples the accepted ticket, and writes:

  .build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg
  .build/release-artifacts/appcast.xml

By default this does not install the app, register the LaunchAgent, or submit a
sysext activation request on the build machine. Set OJD_INSTALL_AFTER_PACKAGE=1
to install the verified app into /Applications after packaging.
TXT
}

cmd="${1:-}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  usage
  exit 0
fi

[[ "$cmd" == "release" || "$cmd" == "appcast" ]] \
  || die "Unknown package command: ${cmd:-<empty>} (expected: release | appcast)"
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
appcast_workspace="$PROJECT_DIR/.build/sparkle-appcast"

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

find_sparkle_tool() {
  local tool_name="$1"
  local candidate
  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(/usr/bin/find "$PROJECT_DIR/.build" -path "*/Sparkle/bin/$tool_name" -type f 2>/dev/null)
  return 1
}

create_appcast() {
  local tag="$1"
  local download_base="${SPARKLE_DOWNLOAD_BASE_URL:-https://github.com/xsyetopz/OpenJoystickDriver/releases/download/$tag}"
  local feed_url="${SPARKLE_FEED_URL:-https://github.com/xsyetopz/OpenJoystickDriver/releases/latest/download/appcast.xml}"
  local appcast_name
  appcast_name="$(basename "$feed_url")"
  [[ "$appcast_name" == *.xml ]] || appcast_name="appcast.xml"
  local private_key="${SPARKLE_ED_PRIVATE_KEY:-}"
  [[ -n "$private_key" ]] || die "SPARKLE_ED_PRIVATE_KEY not set"
  local generate_appcast
  if ! generate_appcast="$(find_sparkle_tool generate_appcast)"; then
    echo "Sparkle generate_appcast not found; resolving package artifacts..."
    (cd "$PROJECT_DIR" && "$SWIFT_BIN" package resolve)
    generate_appcast="$(find_sparkle_tool generate_appcast)" \
      || die "Sparkle generate_appcast not found under .build after package resolve"
  fi

  rm -rf "$appcast_workspace"
  mkdir -p "$appcast_workspace" "$artifact_dir"
  local dmg="$artifact_dir/OpenJoystickDriver-${safe_version}-macOS.dmg"
  [[ -f "$dmg" ]] || die "Release DMG not found: $dmg"
  cp "$dmg" "$appcast_workspace/"

  printf '%s' "$private_key" | "$generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$download_base" \
    "$appcast_workspace"

  [[ -f "$appcast_workspace/$appcast_name" ]] \
    || die "Sparkle appcast was not generated: $appcast_workspace/$appcast_name"
  cp "$appcast_workspace/$appcast_name" "$artifact_dir/appcast.xml"
  for delta in "$appcast_workspace"/*.delta; do
    [[ -f "$delta" ]] && cp "$delta" "$artifact_dir/"
  done

  echo ""
  echo "Sparkle appcast ready:"
  echo "  $artifact_dir/appcast.xml"
}

if [[ "$cmd" == "appcast" ]]; then
  create_appcast "$version"
  exit 0
fi

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

verify_release_app_entitlements() {
  local target_app="$1"
  local target_daemon="$target_app/Contents/Library/LoginItems/OpenJoystickDriverDaemon.app"

  [[ -d "$target_app" ]] || die "App bundle not found: $target_app"
  [[ -d "$target_daemon" ]] || die "Daemon bundle not found: $target_daemon"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$target_app"
  verify_gui_app_signed_entitlements "$target_app"
  verify_daemon_app_signed_entitlements "$target_daemon"
}

install_packaged_app() {
  local source_app="$1"
  local dest_app="/Applications/OpenJoystickDriver.app"

  echo ""
  echo "=== Install verified app to /Applications ==="
  verify_release_app_entitlements "$source_app"
  /bin/rm -rf "$dest_app"
  /usr/bin/ditto "$source_app" "$dest_app"
  verify_release_app_entitlements "$dest_app"
  /usr/sbin/spctl --assess --type execute --verbose=4 "$dest_app"
  echo "Installed: $dest_app"
}

mkdir -p "$artifact_dir"

echo "=== Build release app bundle ==="
OJD_ENV=release /usr/bin/env bash "$SCRIPT_DIR/ojd-build.sh" build release

echo ""
echo "=== Build and embed DriverKit extension ==="
OJD_ENV=release OJD_SKIP_INSTALL=1 /usr/bin/env bash "$SCRIPT_DIR/ojd-build.sh" build dext

[[ -d "$app_path" ]] || die "App bundle not found: $app_path"

echo ""
echo "=== Verify signed app before notarization ==="
verify_release_app_entitlements "$app_path"

echo ""
echo "=== Notarize and staple ==="
OJD_ENV=release \
  OJD_NOTARIZE_APP="$app_path" \
  OJD_NOTARIZE_ZIP="$notary_zip" \
  /usr/bin/env bash "$SCRIPT_DIR/ojd-notarize.sh" submit

echo ""
echo "=== Verify notarized app ==="
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"
verify_release_app_entitlements "$app_path"

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
if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY:-}" != "-" ]]; then
  /usr/bin/codesign --sign "$CODESIGN_IDENTITY" --timestamp "$artifact_dmg"
  /usr/bin/codesign --verify --verbose=2 "$artifact_dmg"
else
  echo "WARNING: CODESIGN_IDENTITY not set; skipping DMG codesign." >&2
fi
/usr/bin/hdiutil verify "$artifact_dmg"
verify_release_app_entitlements "$app_path"

if [[ "${OJD_INSTALL_AFTER_PACKAGE:-0}" == "1" ]]; then
  install_packaged_app "$app_path"
fi

echo ""
echo "Release artifact ready:"
echo "  $artifact_dmg"
