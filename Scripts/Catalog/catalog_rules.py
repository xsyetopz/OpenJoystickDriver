"""Load the authored catalog rule tables from `Resources/CatalogRules/`."""

from __future__ import annotations

import pathlib
import plistlib
from typing import Any

from Scripts.Quality.repository_tool import api_version

ROOT = pathlib.Path(__file__).resolve().parents[2]
RULES_DIR = ROOT / "Resources" / "CatalogRules"


class RulesError(ValueError):
    pass


def load_rules(
    name: str,
    kind: str,
    keys: frozenset[str],
    directory: pathlib.Path = RULES_DIR,
) -> dict[str, Any]:
    """Returns the document `name` after checking its `apiVersion`, `kind` and key set."""
    path = directory / name
    try:
        document = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise RulesError(f"{path}: {error}") from error
    if not isinstance(document, dict):
        raise RulesError(f"{path}: expected a property list dictionary")
    expected = api_version()
    if document.get("apiVersion") != expected:
        raise RulesError(
            f"{path}: apiVersion {document.get('apiVersion')!r}, expected {expected!r}"
        )
    if document.get("kind") != kind:
        raise RulesError(f"{path}: kind {document.get('kind')!r}, expected {kind!r}")
    found = set(document) - {"apiVersion", "kind"}
    if found != keys:
        raise RulesError(
            f"{path}: keys differ from {sorted(keys)}: "
            f"missing {sorted(keys - found)}, unexpected {sorted(found - keys)}"
        )
    return document


def parse_id(text: str) -> int:
    """Parses a four-digit hexadecimal vendor or product ID such as `045E`."""
    if len(text) != 4:
        raise RulesError(f"invalid ID {text!r}: expected four hexadecimal digits")
    try:
        return int(text, 16)
    except ValueError as error:
        raise RulesError(f"invalid ID {text!r}") from error


def parse_identity(text: str) -> tuple[int, int]:
    """Parses `VVVV:PPPP` into (vendor ID, product ID)."""
    vendor, separator, product = text.partition(":")
    if not separator:
        raise RulesError(f"invalid identity {text!r}: expected VVVV:PPPP")
    return parse_id(vendor), parse_id(product)
