"""Check or rebuild the control crosswalk table of the wiki.

`Resources/Vocabulary/crosswalk.json` is the only authored crosswalk.
This script rewrites the generated block of `wiki/Controller-Records.md` from it.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CROSSWALK = Path("Resources/Vocabulary/crosswalk.json")
WIKI_PAGE = Path("wiki/Controller-Records.md")
BEGIN = "<!-- BEGIN GENERATED: control-crosswalk -->"
END = "<!-- END GENERATED: control-crosswalk -->"
COLUMNS = (
    ("w3c", "W3C"),
    ("sdl", "SDL3"),
    ("evdev", "evdev"),
    ("hid", "HID page:usage"),
    ("apple", "Apple GameController"),
)


class CrosswalkError(Exception):
    pass


def load(root: Path) -> dict[str, Any]:
    document = json.loads((root / CROSSWALK).read_text(encoding="utf-8"))
    for key in ("sources", "controls"):
        if not isinstance(document.get(key), dict):
            raise CrosswalkError(f"{CROSSWALK} needs the object {key}")
    for column, _ in COLUMNS:
        if column not in document["sources"]:
            raise CrosswalkError(
                f"{CROSSWALK} records no source for the column {column}"
            )
    return document


def code(value: object) -> str:
    """A cell: the name in code font, or a dash for an absent key (no equivalent)."""
    return "-" if value is None else f"`{value}`"


def w3c_cell(row: dict[str, Any]) -> str:
    button, axis = row.get("w3cButton"), row.get("w3cAxis")
    if button is not None and axis is not None:
        raise CrosswalkError("a control is a W3C button or a W3C axis, not both")
    if button is not None:
        return f"button {button}"
    if axis is not None:
        return f"axis {axis}"
    return "-"


def hid_cell(row: dict[str, Any]) -> str:
    entries = [
        f"`{entry['page']}:{hex(entry['usage']) if 'usage' in entry else 'device'}`"
        for entry in row.get("hid", [])
    ]
    return ", ".join(entries) if entries else "-"


def cell(row: dict[str, Any], column: str) -> str:
    if column == "w3c":
        return w3c_cell(row)
    if column == "hid":
        return hid_cell(row)
    return code(row.get(column))


def wiki_block(document: dict[str, Any]) -> str:
    controls = document["controls"]
    lines = [BEGIN, ""]
    lines.append("| Control | " + " | ".join(title for _, title in COLUMNS) + " |")
    lines.append("| --- |" + " --- |" * len(COLUMNS))
    for control, row in controls.items():
        cells = " | ".join(cell(row, column) for column, _ in COLUMNS)
        lines.append(f"| `{control}` | {cells} |")
    lines += ["", "Each column is checked against this source:", ""]
    lines.append("| Column | Document | Version | Revision | Checked on |")
    lines.append("| --- | --- | --- | --- | --- |")
    for column, title in COLUMNS:
        source = document["sources"][column]
        missing = [
            field for field in ("document", "version", "url") if field not in source
        ]
        if missing:
            raise CrosswalkError(f"the {column} source lacks {', '.join(missing)}")
        name = f"[{source['document']}]({source['url']})"
        revision = code(source.get("revision"))
        lines.append(
            f"| {title} | {name} | {source['version']} | {revision} | {source['checkedOn']} |"
        )
    titles = dict(COLUMNS)
    notes = [
        (control, column, text)
        for control, row in controls.items()
        for column, text in row.get("notes", {}).items()
    ]
    if notes:
        lines += [
            "",
            "Notes on single cells:",
            "",
            "| Control | Column | Note |",
            "| --- | --- | --- |",
        ]
        for control, column, text in notes:
            if column not in titles:
                raise CrosswalkError(
                    f"{control} has a note for the unknown column {column}"
                )
            lines.append(f"| `{control}` | {titles[column]} | {text} |")
    lines += ["", END]
    return "\n".join(lines)


def render_wiki(page: str, block: str) -> str:
    start, end = page.find(BEGIN), page.find(END)
    if start < 0 or end < start:
        raise CrosswalkError(f"{WIKI_PAGE} needs the lines {BEGIN} and {END}")
    return page[:start] + block + page[end + len(END) :]


def outputs(root: Path) -> dict[Path, str]:
    """The derived files as they should be, keyed by path relative to `root`."""
    page = (root / WIKI_PAGE).read_text(encoding="utf-8")
    return {WIKI_PAGE: render_wiki(page, wiki_block(load(root)))}


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
    except (CrosswalkError, OSError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.check and stale:
        names = ", ".join(path.as_posix() for path in stale)
        print(
            f"ERROR: out of date: {names}. Run ./Scripts/ojd vocabulary regenerate --write.",
            file=sys.stderr,
        )
        return 1
    print(f"{'Verified' if args.check else 'Generated'} the control crosswalk table.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
