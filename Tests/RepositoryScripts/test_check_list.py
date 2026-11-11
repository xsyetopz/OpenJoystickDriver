"""One check list: the `check` recipe of the justfile is canonical.

CI and the release gate must run the same commands.

Documented exemptions, kept deliberately small:
- the justfile's whitespace check on the working tree (`JUSTFILE_ONLY`) has no CI counterpart,
  and the justfile prefixes swiftlint with a DEVELOPER_DIR lookup that CI sets through
  `env:`; the lookup is stripped before comparing.
- CI steps that only prepare the runner (toolchain probe, Homebrew cleanup and installs, and
  venv setup) and the `OJD_USE_LOCAL_SWIFTERKIT` guard are not checks of the tree.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

JUSTFILE_ONLY = {"git diff --check"}
CI_ONLY_STEPS = {
    "Toolchain",
    "Remove unused untrusted Homebrew taps",
    "Install dependencies",
}
CI_ONLY_COMMANDS = {'test "$OJD_USE_LOCAL_SWIFTERKIT" = "0"'}
JUSTFILE_ROOT_RECIPES = ("check",)
# (workflow, job, first step, last step): the release job also resolves tags, signs, and publishes;
# only its gate steps, from the first to the last named step, must match the canonical list.
WORKFLOWS = {
    "ci": (".github/workflows/ci.yml", "macos-swiftpm", None, None),
    "release": (
        ".github/workflows/release.yml",
        "package",
        "Remove unused untrusted Homebrew taps",
        "Build and test package",
    ),
}


def normalize(command: str) -> str:
    return " ".join(command.split())


def join_continuations(lines: list[str]) -> list[str]:
    commands: list[str] = []
    pending = ""
    for line in lines:
        stripped = line.strip()
        if not stripped and not pending:
            continue
        if stripped.endswith("\\") and not stripped.endswith("\\\\"):
            pending += stripped[:-1].rstrip() + " "
            continue
        commands.append(normalize(pending + stripped))
        pending = ""
    return commands


def justfile_commands() -> list[str]:
    recipes: dict[str, tuple[list[str], list[str]]] = {}
    current: list[str] | None = None
    header_pattern = re.compile(r"^([A-Za-z][\w-]*)(?:\s+\*?\w+)*:(?:\s+([\w\s-]*))?$")
    for line in (ROOT / "justfile").read_text(encoding="utf-8").splitlines():
        header = header_pattern.match(line)
        if header:
            current = []
            recipes[header.group(1)] = ((header.group(2) or "").split(), current)
        elif line.startswith("    ") and current is not None:
            current.append(line[4:])
        elif line.strip() and not line.startswith("#"):
            current = None

    commands: list[str] = []
    seen: set[str] = set()

    def visit(name: str) -> None:
        if name in seen:
            return
        seen.add(name)
        dependencies, body = recipes[name]
        for dependency in dependencies:
            visit(dependency)
        for command in join_continuations(body):
            command = re.sub(r'^xcode=.*?; DEVELOPER_DIR="\$xcode" ', "", command)
            if command not in JUSTFILE_ONLY:
                commands.append(command)

    for name in JUSTFILE_ROOT_RECIPES:
        visit(name)
    return commands


def workflow_commands(key: str) -> list[str]:
    path, job, first, last = WORKFLOWS[key]
    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
    active = first is None
    commands: list[str] = []
    step = ""
    index = 0
    in_job = False
    while index < len(lines):
        line = lines[index]
        index += 1
        if re.match(r"^  \w[\w-]*:\s*$", line):
            in_job = line.strip() == f"{job}:"
            continue
        if not in_job:
            continue
        name = re.match(r"^\s+- name:\s*(.+?)\s*$", line)
        if name:
            step = name.group(1)
            active = active or step == first
            continue
        run = re.match(r"^(\s+)run:\s*(.*)$", line)
        if not run or not active or step in CI_ONLY_STEPS:
            continue
        if run.group(2) not in ("|", ">"):
            commands.append(normalize(run.group(2)))
        else:
            body: list[str] = []
            while index < len(lines) and (
                not lines[index].strip() or lines[index].startswith(run.group(1) + "  ")
            ):
                body.append(lines[index])
                index += 1
            commands.extend(join_continuations(body))
        if step == last:
            break
    return [command for command in commands if command not in CI_ONLY_COMMANDS]


class CheckListTests(unittest.TestCase):
    def setUp(self) -> None:
        self.canonical = justfile_commands()

    def assert_same(self, name: str, actual: list[str]) -> None:
        self.assertEqual(len(actual), len(set(actual)), f"{name} repeats a command")
        self.assertEqual(
            sorted(set(self.canonical) - set(actual)), [], f"{name} is missing commands"
        )
        self.assertEqual(
            sorted(set(actual) - set(self.canonical)),
            [],
            f"{name} has commands that `just check` does not run",
        )

    def test_the_canonical_list_has_no_repeats_and_names_the_core_checks(self) -> None:
        self.assertEqual(len(self.canonical), len(set(self.canonical)))
        for required in (
            "./Scripts/ojd errors regenerate --check",
            "./Scripts/ojd check tools",
            "./Scripts/ojd test parsers-macos14",
            "./Scripts/ojd snapshots check",
            "python3 Scripts/Quality/check_localization_keys.py",
            "python3 Scripts/Quality/check_text_styles.py",
            "./Scripts/ojd check swift",
        ):
            self.assertIn(required, self.canonical)

    def test_ci_runs_the_canonical_list(self) -> None:
        self.assert_same(WORKFLOWS["ci"][0], workflow_commands("ci"))

    def test_the_release_gate_runs_the_canonical_list(self) -> None:
        self.assert_same(WORKFLOWS["release"][0], workflow_commands("release"))


if __name__ == "__main__":
    unittest.main()
