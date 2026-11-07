"""Format JSON text the way the repository writes generated JSON files.

The layout is Swift's `OrderedJSON.formatted()`, which `OJDRepositoryTool format-json` applies.
"""

from __future__ import annotations

import pathlib
import subprocess
import tempfile

from Scripts.Quality import repository_tool


def format_json(texts: dict[pathlib.Path, str]) -> dict[pathlib.Path, str]:
    """Returns each text as `OrderedJSON.formatted()` writes it; a key names only the result."""
    if not texts:
        return {}
    with tempfile.TemporaryDirectory() as directory:
        staged = {
            path: pathlib.Path(directory) / f"{index}.json"
            for index, path in enumerate(texts)
        }
        for path, text in texts.items():
            staged[path].write_text(text, encoding="utf-8")
        result = subprocess.run(
            [str(repository_tool.binary()), "format-json", *map(str, staged.values())],
            capture_output=True,
            check=False,
            text=True,
        )
        if result.returncode:
            raise repository_tool.ToolError(
                f"{repository_tool.PRODUCT} format-json exited {result.returncode}: "
                f"{result.stderr.strip()}"
            )
        return {
            path: temporary.read_text(encoding="utf-8")
            for path, temporary in staged.items()
        }
