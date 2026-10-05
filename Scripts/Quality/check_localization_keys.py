"""Fail when a localization key used in Swift code is missing from the en-US catalog.

English text lives only in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj`. Call sites pass a key
and nothing else, so a key that is absent from that catalog would render as the raw key.

The scan reads the first argument of `OJDLocalized.*`, `CLILocalized.*`, `LocalizedStringResource(`,
and `Localization().*` / `localization.*` calls. A literal key must exist exactly. A ternary of
literals must have both keys. A key built from a literal prefix, such as `"error.\\(rawValue)"` or
`"profiles.stick." + key`, must have at least one catalog key with that prefix. Other dynamic keys
cannot be checked and are listed.
"""

from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources/en-US.lproj")
CALL = re.compile(
    r"\b(?:OJDLocalized\.(?:string|formatted|plural)|CLILocalized\.(?:text|format)"
    r"|LocalizedStringResource|(?:Localization\(\)|localization)\.(?:string|formatted|plural))\("
)
STRINGS_KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


@dataclass(frozen=True)
class KeyUse:
    path: str
    line: int
    expression: str


def skip_string(source: str, index: int) -> int:
    """Return the index after the string literal that starts at `index`."""
    index += 1
    while True:
        character = source[index]
        if character == "\\":
            if source[index + 1] == "(":
                index = skip_group(source, index + 1)
            else:
                index += 2
        elif character == '"':
            return index + 1
        else:
            index += 1


def skip_group(source: str, index: int) -> int:
    """Return the index after the bracket group that starts at `index`."""
    depth = 0
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1


def first_argument(source: str, open_index: int) -> str:
    """Return the text of the first argument of the call whose `(` is at `open_index`."""
    depth = 0
    index = open_index + 1
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif character == "," and depth == 0:
            break
        index += 1
    return source[open_index + 1 : index].strip()


def key_arguments(source: str) -> list[tuple[int, str]]:
    """Return (line, first-argument text) for each localization call in `source`."""
    return [
        (
            source.count("\n", 0, match.start()) + 1,
            first_argument(source, match.end() - 1),
        )
        for match in CALL.finditer(source)
    ]


def catalog_keys(root: Path = ROOT) -> set[str]:
    """Return the keys of the en-US `.strings` and `.stringsdict` catalogs."""
    directory = root / CATALOG_DIRECTORY
    strings = (directory / "Localizable.strings").read_text(encoding="utf-8")
    keys = set(STRINGS_KEY.findall(strings))
    keys.update(plistlib.loads((directory / "Localizable.stringsdict").read_bytes()))
    return keys


def problems(expression: str, keys: set[str]) -> str | None:
    """Return why `expression` names a missing key, or None when it is fine or unscannable."""
    literals = LITERAL.findall(expression)
    if re.fullmatch(r'"[^"\\]*"', expression):
        return None if literals[0] in keys else f"missing key {literals[0]!r}"
    ternary = re.search(r'\?\s*"([^"\\]*)"\s*:\s*"([^"\\]*)"', expression)
    if ternary:
        absent = [key for key in ternary.groups() if key not in keys]
        return f"missing key {absent[0]!r}" if absent else None
    prefix = re.match(r'"([^"\\]*)(?:\\\(|"\s*\+)', expression)
    if prefix and prefix.group(1):
        if any(key.startswith(prefix.group(1)) for key in keys):
            return None
        return f"no key starts with {prefix.group(1)!r}"
    return None


def tracked_swift_files(root: Path = ROOT) -> list[Path]:
    output = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "*.swift",
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [
        root / name for name in output.split("\0") if name and (root / name).exists()
    ]


def check(root: Path = ROOT) -> tuple[list[tuple[KeyUse, str]], list[KeyUse]]:
    """Return (missing keys with reasons, call sites whose key cannot be scanned)."""
    keys = catalog_keys(root)
    missing: list[tuple[KeyUse, str]] = []
    unscannable: list[KeyUse] = []
    for path in tracked_swift_files(root):
        relative = path.relative_to(root).as_posix()
        for line, expression in key_arguments(path.read_text(encoding="utf-8")):
            use = KeyUse(relative, line, expression)
            reason = problems(expression, keys)
            if reason:
                missing.append((use, reason))
            elif not LITERAL.search(expression):
                unscannable.append(use)
    return missing, unscannable


def main() -> int:
    missing, unscannable = check()
    for use, reason in missing:
        print(f"{use.path}:{use.line}: {reason} in the en-US catalog")
    for use in unscannable:
        print(f"{use.path}:{use.line}: key not scanned: {use.expression}")
    if missing:
        print(
            f"error: {len(missing)} localization key(s) missing from en-US",
            file=sys.stderr,
        )
        return 1
    print("Every scannable localization key used in Swift exists in the en-US catalog.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
