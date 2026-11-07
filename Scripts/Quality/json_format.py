"""Format JSON text the way the repository writes generated JSON files."""

from __future__ import annotations

import json
import pathlib


def format_json(texts: dict[pathlib.Path, str]) -> dict[pathlib.Path, str]:
    """Returns each text as two-space indented JSON with a trailing newline."""
    return {
        path: json.dumps(json.loads(text), indent=2, ensure_ascii=False) + "\n"
        for path, text in texts.items()
    }
