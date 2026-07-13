#!/usr/bin/env python3
# Validate the repository script layout and shell syntax.

from __future__ import annotations

import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
OWNERS = {
    "build-tools",
    "catalog",
    "diagnostics",
    "docs",
    "shared",
    "quality",
    "release",
    "signing",
}
DISPATCH_TARGET = re.compile(r'"\$SCRIPT_DIR/([^"]+\.(?:sh|py))"')


def validate_layout(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    scripts = root / "scripts"
    allowed_root_files = {"README.md", "ojd"}

    for path in sorted(scripts.iterdir()):
        if path.name == "__pycache__":
            continue
        if path.is_file() and path.name not in allowed_root_files:
            errors.append(f"{path.relative_to(root)}: implementation must have an owner directory")
        if path.is_dir() and path.name not in OWNERS:
            errors.append(f"{path.relative_to(root)}: unknown owner directory")

    dispatcher = scripts / "ojd"
    if not dispatcher.is_file():
        errors.append("scripts/ojd: stable dispatcher is missing")
        return errors
    if dispatcher.stat().st_mode & 0o111 != 0o111:
        errors.append("scripts/ojd: dispatcher must be executable")

    for path in sorted(scripts.rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts or path == dispatcher:
            continue
        if path.stat().st_mode & 0o111:
            errors.append(f"{path.relative_to(root)}: only scripts/ojd may be executable")

    dispatcher_text = dispatcher.read_text(encoding="utf-8")
    for relative_name in DISPATCH_TARGET.findall(dispatcher_text):
        target = scripts / relative_name
        if not target.is_file():
            errors.append(
                f"scripts/ojd: routed implementation does not exist: scripts/{relative_name}"
            )

    stale_pattern = re.compile(
        r"scripts/(?:ojd-[A-Za-z0-9_.-]+|bump-version\.sh|CATALINA_TESTKIT\.md)"
    )
    direct_internal_pattern = re.compile(r"\./" + r"scripts/(?!ojd(?:[^A-Za-z0-9_.-]|$))")
    shellcheck_suppression = re.compile(r"shellcheck\s+disable=")
    search_roots = [
        root / ".github",
        root / "Tests",
        root / "docs",
        root / "scripts",
        root / "AGENTS.md",
        root / "CONTRIBUTING.md",
        root / "README.md",
        root / "justfile",
    ]
    for tree in search_roots:
        if not tree.exists():
            continue
        paths = [tree] if tree.is_file() else sorted(tree.rglob("*"))
        for path in paths:
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for line_number, line in enumerate(text.splitlines(), start=1):
                if stale_pattern.search(line):
                    errors.append(
                        f"{path.relative_to(root)}:{line_number}: stale flat script path"
                    )
                if direct_internal_pattern.search(line):
                    errors.append(
                        f"{path.relative_to(root)}:{line_number}: invoke scripts/ojd, "
                        "not an implementation path"
                    )
                if shellcheck_suppression.search(line):
                    errors.append(
                        f"{path.relative_to(root)}:{line_number}: ShellCheck suppression "
                        "directives are forbidden"
                    )

    return errors


def validate_shell_syntax(root: Path = ROOT) -> list[str]:
    shell_files = [root / "scripts" / "ojd"]
    shell_files.extend(sorted((root / "scripts").rglob("*.sh")))
    result = subprocess.run(
        ["/usr/bin/env", "bash", "-n", *(str(path) for path in shell_files)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return []
    detail = result.stderr.strip() or result.stdout.strip() or "bash -n failed"
    return [detail]


def main() -> int:
    errors = validate_layout()
    errors.extend(validate_shell_syntax())
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        print(f"Script validation failed with {len(errors)} error(s).", file=sys.stderr)
        return 1
    print("Script validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
