from __future__ import annotations

import difflib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOTS = ROOT / "Tests" / "EquivalenceSnapshots"
TEST_FILTER = "EquivalenceSnapshot"


def parse_sections(text: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    title: str | None = None
    for line in text.splitlines():
        if line.startswith("## "):
            title = line[3:]
            sections[title] = []
        elif title is not None:
            sections[title].append(line)
    return {key: "\n".join(lines).strip("\n") for key, lines in sections.items()}


def parse_header(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        if line.startswith("## "):
            break
        lines.append(line)
    return "\n".join(lines).strip("\n")


def diff_sections(expected: str, actual: str) -> list[str]:
    before = parse_sections(expected)
    after = parse_sections(actual)
    lines: list[str] = []
    old_header = parse_header(expected)
    new_header = parse_header(actual)
    if old_header != new_header:
        lines.append("  changed header")
        lines.extend(f"    - {line}" for line in old_header.splitlines())
        lines.extend(f"    + {line}" for line in new_header.splitlines())
    for title in sorted(before.keys() | after.keys()):
        if title not in after:
            lines.append(f"  removed {title}")
        elif title not in before:
            lines.append(f"  added   {title}")
        elif before[title] != after[title]:
            lines.append(f"  changed {title}")
            lines.extend(changed_lines(before[title], after[title]))
    return lines


def changed_lines(expected: str, actual: str) -> list[str]:
    old = expected.splitlines()
    new = actual.splitlines()
    lines: list[str] = []
    matcher = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        lines.extend(f"    - {line}" for line in old[i1:i2])
        lines.extend(f"    + {line}" for line in new[j1:j2])
    return lines


def diff_document(expected: str, actual: str) -> list[str]:
    if expected == actual:
        return []
    return ["  changed document", *changed_lines(expected, actual)]


SNAPSHOT_PATTERNS = ("*.txt", "*.json")


def compare(snapshots: Path, actual: Path) -> dict[str, list[str]]:
    names = {
        path.name
        for directory in (snapshots, actual)
        for pattern in SNAPSHOT_PATTERNS
        for path in directory.glob(pattern)
    }
    result: dict[str, list[str]] = {}
    for name in sorted(names):
        recorded = snapshots / name
        current = actual / name
        if not current.is_file():
            result[name] = ["  no longer produced by the tree"]
            continue
        expected_text = recorded.read_text() if recorded.is_file() else ""
        differ = diff_document if name.endswith(".json") else diff_sections
        difference = differ(expected_text, current.read_text())
        if not recorded.is_file():
            difference = ["  snapshot file is missing", *difference]
        if difference:
            result[name] = difference
    return result


def run_tests(extra: dict[str, str]) -> int:
    environment = os.environ.copy()
    environment.update(extra)
    return subprocess.run(
        [str(ROOT / "Scripts/with-env.sh"), "swift", "test", "--filter", TEST_FILTER],
        cwd=ROOT,
        env=environment,
        check=False,
    ).returncode


def check() -> int:
    with tempfile.TemporaryDirectory(prefix="ojd-snapshots-") as directory:
        status = run_tests({"OJD_SNAPSHOT_ACTUAL_DIR": directory})
        if status != 0:
            print("error: the snapshot tests did not run", file=sys.stderr)
            return status
        differences = compare(SNAPSHOTS, Path(directory))
    if not differences:
        print("No differences from the equivalence snapshots.")
        return 0
    count = sum(
        1
        for lines in differences.values()
        for line in lines
        if not line.startswith("    ")
    )
    for name, lines in differences.items():
        print(f"{name}:")
        print("\n".join(lines))
    print(f"{count} difference(s). Run just snapshots-write to accept them.")
    return 1


def write() -> int:
    status = run_tests({"OJD_SNAPSHOT_WRITE": "1"})
    if status == 0:
        print(f"Rewrote the equivalence snapshots in {SNAPSHOTS.relative_to(ROOT)}.")
    return status


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if arguments == ["check"]:
        return check()
    if arguments == ["write"]:
        return write()
    print("error: expected: check | write", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
