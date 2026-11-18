from __future__ import annotations

import plistlib
from functools import cache
from pathlib import Path
from typing import Any

PROTOCOLS = Path(__file__).resolve().parents[2] / "Resources" / "Protocols"


@cache
def bundled() -> dict[str, dict[str, Any]]:
    descriptions: dict[str, dict[str, Any]] = {}
    for path in sorted(PROTOCOLS.glob("*.plist")):
        document = plistlib.loads(path.read_bytes())
        descriptions[document["family"]] = document
    return descriptions


def stores_variant(description: dict[str, Any]) -> bool:
    return description.get("storesVariant", False)
