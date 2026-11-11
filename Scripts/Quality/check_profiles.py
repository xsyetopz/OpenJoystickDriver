from __future__ import annotations

import sys

from . import repository_tool

RECORD_DIR = (
    repository_tool.ROOT
    / "Sources"
    / "OpenJoystickDriverKit"
    / "Resources"
    / "Controllers"
)


def main() -> int:
    try:
        repository_tool.check(["validate", "controllers", str(RECORD_DIR)])
    except repository_tool.ToolError as error:
        for line in str(error).splitlines():
            print(f"[FAIL] {line}", file=sys.stderr)
        return 1
    print(
        f"Validated {len(list(RECORD_DIR.rglob('*.plist')))} canonical controller record(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
