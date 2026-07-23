#!/usr/bin/env bash
# Update OpenJoystickDriver release version references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd bump-version <version>

Examples:
  ./scripts/ojd bump-version 0.1.0-rc.2
  ./scripts/ojd bump-version 0.1.0

Updates:
  - justfile release-local-install default
  - scripts/README.md release examples
  - scripts/platform/environment.sh app and generated DriverKit default version
  - Release-version packaging assertions

The target version must already have a CHANGELOG.md heading.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

version="${1:-}"
if [[ "$version" == "" || "$version" == "-h" || "$version" == "--help" || "$version" == "help" ]]; then
  usage
  exit 0
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  die "Version must be SemVer, for example 0.1.0-rc.2"
fi

packaging_tests="$PROJECT_DIR/Tests/OpenJoystickDriverKitTests/Integration/Packaging/ScriptPackagingTests.swift"
justfile="$PROJECT_DIR/justfile"
scripts_readme="$PROJECT_DIR/scripts/README.md"
build_defaults="$PROJECT_DIR/scripts/platform/environment.sh"
changelog="$PROJECT_DIR/CHANGELOG.md"

[[ -f "$packaging_tests" ]] || die "Missing $packaging_tests"
[[ -f "$justfile" ]] || die "Missing $justfile"
[[ -f "$scripts_readme" ]] || die "Missing $scripts_readme"
[[ -f "$build_defaults" ]] || die "Missing $build_defaults"
[[ -f "$changelog" ]] || die "Missing $changelog"

if ! grep -Fxq "## $version" "$changelog"; then
  die "CHANGELOG.md must contain heading: ## $version"
fi

python3 - "$version" "$packaging_tests" "$justfile" "$scripts_readme" "$build_defaults" <<'PY'
import re
import sys
from pathlib import Path

(
    version,
    packaging_tests_path,
    justfile_path,
    readme_path,
    build_defaults_path,
) = sys.argv[1:]

replacements = [
    (
        Path(packaging_tests_path),
        [
            (
                "packaging test release-local-install versions",
                re.compile(
                    r'(release-local-install version=\\")\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(\\")'
                ),
                rf"\g<1>{version}\g<2>",
                2,
            ),
        ],
    ),
    (
        Path(justfile_path),
        [
            (
                "justfile release-local-install default",
                re.compile(
                    r'release-local-install version="\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?":'
                ),
                f'release-local-install version="{version}":',
                1,
            ),
        ],
    ),
    (
        Path(readme_path),
        [
            (
                "scripts README package release example",
                re.compile(
                    r"\./scripts/ojd package release \d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"./scripts/ojd package release {version}",
                1,
            ),
            (
                "scripts README manual dispatch version example",
                re.compile(
                    r"`\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?` and by manual dispatch"
                ),
                f"`{version}` and by manual dispatch",
                1,
            ),
        ],
    ),
    (
        Path(build_defaults_path),
        [
            (
                "shared app and DriverKit default short version",
                re.compile(
                    r'(OJD_DEFAULT_BUNDLE_SHORT_VERSION=")\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(")'
                ),
                rf"\g<1>{version}\g<2>",
                1,
            ),
        ],
    ),
]

missing = []
updates = []
for path, patterns in replacements:
    text = path.read_text()
    updated = text
    file_missing = False
    for description, pattern, repl, minimum in patterns:
        updated, count = pattern.subn(repl, updated)
        if count < minimum:
            missing.append(f"{path}: {description} (expected at least {minimum}, found {count})")
            file_missing = True
    if not file_missing and updated != text:
        updates.append((path, updated))

if missing:
    for item in missing:
        print(f"missing expected version reference: {item}", file=sys.stderr)
    sys.exit(1)

changed = []
for path, updated in updates:
    path.write_text(updated)
    changed.append(str(path))

for path in changed:
    print(f"updated {path}")
if not changed:
    print("version references already up to date")
PY

echo "Version set to $version"
