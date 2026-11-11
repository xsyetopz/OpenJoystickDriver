"""Check or rebuild everything that derives from the error code catalog.

`Resources/ErrorCodes.plist` is the only authored list of E#### codes.
This script validates it,
and rewrites the two files that copy it:
the `code` enum of `Resources/Schemas/endpoint.schema.json`
and the generated block of `wiki/Error-Codes.md`.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path
from typing import Any

from Scripts.Quality.repository_tool import (
    command_line_exit_statuses,
    domain_areas,
    domain_code_prefixes,
)

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r Scripts/Quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
CATALOG = Path("Resources/ErrorCodes.plist")
CATALOG_SCHEMA = Path("Resources/Schemas/error-codes.schema.json")
ENDPOINT_SCHEMA = Path("Resources/Schemas/endpoint.schema.json")
WIKI_PAGE = Path("wiki/Error-Codes.md")
ENGLISH_STRINGS = Path(
    "Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings"
)
BEGIN = "<!-- BEGIN GENERATED: error-codes -->"
END = "<!-- END GENERATED: error-codes -->"
STRING_LINE = re.compile(r'^"([^"]+)" = "(.*)";$')
STRING_ESCAPE = re.compile(r"\\(.)")
STRING_ESCAPES = {"n": "\n", "t": "\t"}
ENDPOINT_ENUM = re.compile(
    r'("error": \{.*?"code": \{[^{}\]]*?"enum": \[)[^\]]*(\])', re.DOTALL
)

Entry = dict[str, Any]


class ErrorCodeError(Exception):
    pass


def load_catalog(root: Path) -> list[Entry]:
    document = plistlib.loads((root / CATALOG).read_bytes())
    with (root / CATALOG_SCHEMA).open(encoding="utf-8") as source:
        schema = json.load(source)
    problems = [
        f"{'/'.join(str(part) for part in error.absolute_path) or 'catalog'}: {error.message}"
        for error in Draft202012Validator(schema).iter_errors(document)
    ]
    if problems:
        raise ErrorCodeError(
            f"{CATALOG} breaks its schema:\n  " + "\n  ".join(problems)
        )
    return document["codes"]


def check_invariants(entries: list[Entry]) -> None:
    problems: list[str] = []
    prefixes = domain_code_prefixes()
    codes = [entry["code"] for entry in entries]
    names = [entry["name"] for entry in entries]
    for label, items in (("code", codes), ("name", names)):
        problems += [
            f"{label} {item} is used twice"
            for item in sorted({item for item in items if items.count(item) > 1})
        ]
    problems += [
        f"{entry['code']} is in the {entry['domain']} domain, which uses {prefixes[entry['domain']]}xxx"
        for entry in entries
        if not entry["code"].startswith(prefixes[entry["domain"]])
    ]
    wires = [entry["wire"] for entry in entries if "wire" in entry]
    problems += [
        f"wire {wire} is used twice"
        for wire in sorted({wire for wire in wires if wires.count(wire) > 1})
    ]
    exit_codes = command_line_exit_statuses()
    problems += [
        f"{entry['code']} has exit code {entry['exitCode']}, which ojd does not document "
        f"(use one of {', '.join(str(code) for code in sorted(exit_codes))})"
        for entry in entries
        if "exitCode" in entry and entry["exitCode"] not in exit_codes
    ]
    if codes != sorted(codes):
        problems.append("entries are not sorted by code")
    # The codes of an area run from 001 without a gap.
    for prefix in prefixes.values():
        area = sorted(code for code in codes if code.startswith(prefix))
        problems += [
            f"{code} skips {wanted}; a new code is the highest code of its area plus one"
            for code, wanted in zip(
                area, (f"{prefix}{number:03d}" for number in range(1, len(area) + 1))
            )
            if code != wanted
        ][:1]
    if problems:
        raise ErrorCodeError(f"{CATALOG} breaks its rules:\n  " + "\n  ".join(problems))


def english_strings(root: Path) -> dict[str, str]:
    strings: dict[str, str] = {}
    for line in (root / ENGLISH_STRINGS).read_text(encoding="utf-8").splitlines():
        match = STRING_LINE.match(line)
        if match:
            strings[match.group(1)] = STRING_ESCAPE.sub(
                lambda escape: STRING_ESCAPES.get(escape[1], escape[1]), match.group(2)
            )
    return strings


def meaning(entry: Entry, strings: dict[str, str]) -> str:
    key = f"error.{entry['code']}.message"
    if key not in strings:
        raise ErrorCodeError(f"{ENGLISH_STRINGS.name} has no key {key}")
    text = strings[key].replace("|", "\\|")
    if "exitCode" in entry:
        text += f" Exit code {entry['exitCode']}."
    if "wire" in entry:
        text += f" Wire value `{entry['wire']}`."
    return text


def wiki_block(entries: list[Entry], strings: dict[str, str]) -> str:
    areas = domain_areas()
    rows = [
        f"| {entry['code']} | {areas[entry['domain']]} | {meaning(entry, strings)} |"
        for entry in entries
    ]
    return "\n".join(
        [BEGIN, "| Code | Area | Meaning |", "| --- | --- | --- |", *rows, END]
    )


def render_wiki(page: str, block: str) -> str:
    start, end = page.find(BEGIN), page.find(END)
    if start < 0 or end < start:
        raise ErrorCodeError(f"{WIKI_PAGE} needs the lines {BEGIN} and {END}")
    return page[:start] + block + page[end + len(END) :]


def render_endpoint_schema(text: str, entries: list[Entry]) -> str:
    codes = [entry["code"] for entry in entries if entry["domain"] == "Endpoint"]
    expected = json.loads(text)
    try:
        expected["$defs"]["error"]["properties"]["code"]["enum"] = codes
    except (KeyError, TypeError) as error:
        raise ErrorCodeError(f"{ENDPOINT_SCHEMA} has no error code enum") from error
    # Another object can also hold an "error" key; take the match that changes only this enum.
    for match in ENDPOINT_ENUM.finditer(text):
        key_line = match[1].rsplit("\n", 1)[-1]
        indent = key_line[: len(key_line) - len(key_line.lstrip())]
        items = ",\n".join(f"{indent}  {json.dumps(code)}" for code in codes)
        rendered = (
            text[: match.start()]
            + match[1]
            + f"\n{items}\n{indent}"
            + match[2]
            + text[match.end() :]
        )
        if json.loads(rendered) == expected:
            return rendered
    raise ErrorCodeError(f"{ENDPOINT_SCHEMA} has no error code enum")


def outputs(root: Path) -> dict[Path, str]:
    """The derived files as they should be, keyed by path relative to `root`."""
    entries = load_catalog(root)
    check_invariants(entries)
    strings = english_strings(root)
    endpoint = (root / ENDPOINT_SCHEMA).read_text(encoding="utf-8")
    page = (root / WIKI_PAGE).read_text(encoding="utf-8")
    return {
        ENDPOINT_SCHEMA: render_endpoint_schema(endpoint, entries),
        WIKI_PAGE: render_wiki(page, wiki_block(entries, strings)),
    }


def regenerate(root: Path, write: bool) -> list[Path]:
    """Writes the derived files, or returns the ones that differ from their source."""
    stale = []
    for path, text in outputs(root).items():
        if (root / path).read_text(encoding="utf-8") != text:
            stale.append(path)
            if write:
                (root / path).write_text(text, encoding="utf-8")
    return stale


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        stale = regenerate(ROOT, write=args.write)
    except (ErrorCodeError, OSError, plistlib.InvalidFileException, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.check and stale:
        names = ", ".join(path.as_posix() for path in stale)
        print(
            f"ERROR: out of date: {names}. Run ./Scripts/ojd errors regenerate --write.",
            file=sys.stderr,
        )
        return 1
    print(f"{'Verified' if args.check else 'Generated'} the error code catalog.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
