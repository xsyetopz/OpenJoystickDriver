"""Check or rebuild everything that derives from the error code catalog.

`Resources/ErrorCodes.json` is the only authored list of E#### codes.
This script validates it, guards against reusing a released code,
and rewrites the two files that copy it:
the `code` enum of `Resources/Schemas/endpoint.schema.json`
and the generated block of `wiki/Error-Codes.md`.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from Scripts.Quality.schema_compatibility import git, last_release_tag

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
CATALOG = Path("Resources/ErrorCodes.json")
CATALOG_SCHEMA = Path("Resources/Schemas/error-codes.schema.json")
ENDPOINT_SCHEMA = Path("Resources/Schemas/endpoint.schema.json")
WIKI_PAGE = Path("wiki/Error-Codes.md")
TEMPLATE = Path(
    "Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings"
)
BEGIN = "<!-- BEGIN GENERATED: error-codes -->"
END = "<!-- END GENERATED: error-codes -->"
DOMAIN_PREFIX = {"endpoint": "E1", "cli": "E2", "remapping": "E3"}
DOMAIN_AREA = {"endpoint": "Endpoint", "cli": "Command line", "remapping": "Remapping"}
STRING_LINE = re.compile(r'^"([^"]+)" = "(.*)";$')
ENDPOINT_ENUM = re.compile(
    r'("error": \{.*?"code": \{[^{}\]]*?"enum": \[)[^\]]*(\])', re.DOTALL
)

Entry = dict[str, Any]


class ErrorCodeError(Exception):
    pass


def load_catalog(root: Path) -> list[Entry]:
    with (root / CATALOG).open(encoding="utf-8") as source:
        document = json.load(source)
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
    codes = [entry["code"] for entry in entries]
    names = [entry["name"] for entry in entries]
    for label, items in (("code", codes), ("name", names)):
        problems += [
            f"{label} {item} is used twice"
            for item in sorted({item for item in items if items.count(item) > 1})
        ]
    problems += [
        f"{entry['code']} is in the {entry['domain']} domain, which uses {DOMAIN_PREFIX[entry['domain']]}xxx"
        for entry in entries
        if not entry["code"].startswith(DOMAIN_PREFIX[entry["domain"]])
    ]
    if codes != sorted(codes):
        problems.append("entries are not sorted by code")
    if problems:
        raise ErrorCodeError(f"{CATALOG} breaks its rules:\n  " + "\n  ".join(problems))


def check_not_reused(previous: list[Entry], entries: list[Entry]) -> None:
    """Every code of the previous catalog stays, with the same domain and name."""
    current = {entry["code"]: entry for entry in entries}
    problems: list[str] = []
    for old in previous:
        new = current.get(old["code"])
        if new is None:
            problems.append(
                f"{old['code']} ({old['name']}) was deleted; retire it instead"
            )
        elif (new["domain"], new["name"]) != (old["domain"], old["name"]):
            problems.append(
                f"{old['code']} was {old['domain']} {old['name']} "
                f"and is now {new['domain']} {new['name']}; a code is never reused"
            )
    if problems:
        raise ErrorCodeError(
            "a released error code changed:\n  " + "\n  ".join(problems)
        )


def released_catalog(root: Path) -> tuple[str, list[Entry]] | None:
    """The catalog at the last release tag, or None when there is no tag or no catalog."""
    try:
        tag = last_release_tag(root)
        text = git(root, "show", f"{tag}:{CATALOG.as_posix()}")
    except (subprocess.CalledProcessError, OSError):
        print("No release catalog found; skipped the reuse check.", file=sys.stderr)
        return None
    return tag, json.loads(text)["codes"]


def english_strings(root: Path) -> dict[str, str]:
    strings: dict[str, str] = {}
    for line in (root / TEMPLATE).read_text(encoding="utf-8").splitlines():
        match = STRING_LINE.match(line)
        if match:
            strings[match.group(1)] = match.group(2).replace("\\n", "\n")
    return strings


def meaning(entry: Entry, strings: dict[str, str]) -> str:
    if entry["status"] == "retired":
        return f"Retired in {entry['retiredIn']}."
    key = f"error.{entry['code']}"
    if key not in strings:
        raise ErrorCodeError(f"{TEMPLATE.name} has no key {key}")
    text = strings[key].replace("|", "\\|")
    if "exitCode" in entry:
        text += f" Exit code {entry['exitCode']}."
    if "wire" in entry:
        text += f" Wire value `{entry['wire']}`."
    return text


def wiki_block(entries: list[Entry], strings: dict[str, str]) -> str:
    rows = [
        f"| {entry['code']} | {DOMAIN_AREA[entry['domain']]} | {meaning(entry, strings)} |"
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
    codes = [
        entry["code"]
        for entry in entries
        if entry["domain"] == "endpoint" and entry["status"] == "active"
    ]
    indent = "\n" + "\t" * 6
    enum = (
        indent
        + ("," + indent).join(json.dumps(code) for code in codes)
        + "\n"
        + "\t" * 5
    )
    rendered, count = ENDPOINT_ENUM.subn(
        lambda match: match.group(1) + enum + match.group(2), text, count=1
    )
    if count != 1:
        raise ErrorCodeError(f"{ENDPOINT_SCHEMA} has no error code enum")
    return rendered


def outputs(root: Path) -> dict[Path, str]:
    """The derived files as they should be, keyed by path relative to `root`."""
    entries = load_catalog(root)
    check_invariants(entries)
    released = released_catalog(root)
    if released is not None:
        try:
            check_not_reused(released[1], entries)
        except ErrorCodeError as error:
            raise ErrorCodeError(f"{error} (compared with {released[0]})") from error
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
    except (ErrorCodeError, OSError, json.JSONDecodeError) as error:
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
