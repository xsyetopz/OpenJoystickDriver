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
  - Sources/OpenJoystickDriver/App/Info.plist canonical app/package version
  - scripts/README.md release examples

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

app_info="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Info.plist"
scripts_readme="$PROJECT_DIR/scripts/README.md"
changelog="$PROJECT_DIR/CHANGELOG.md"

[[ -f "$app_info" ]] || die "Missing $app_info"
[[ -f "$scripts_readme" ]] || die "Missing $scripts_readme"
[[ -f "$changelog" ]] || die "Missing $changelog"

if ! grep -Fxq "## $version" "$changelog"; then
  die "CHANGELOG.md must contain heading: ## $version"
fi

python3 - "$version" "$app_info" "$scripts_readme" <<'PY'
import re
import sys
from pathlib import Path

(
    version,
    app_info_path,
    readme_path,
) = sys.argv[1:]

replacements = [
    (
        Path(app_info_path),
        [
            (
                "canonical app/package short version",
                re.compile(
                    r'(<key>CFBundleShortVersionString</key>\s*<string>)'
                    r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?'
                    r'(</string>)'
                ),
                rf'\g<1>{version}\g<2>',
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
                    r"\./scripts/ojd release package \d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"./scripts/ojd release package {version}",
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
