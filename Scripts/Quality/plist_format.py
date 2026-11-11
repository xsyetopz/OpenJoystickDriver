"""Write documents in the canonical property list form that `DocumentCoder` writes.

Swift owns the form (`swift_canonical`): `OJDRepositoryTool to-plist` reads JSON files and writes
each as the `.plist` beside it, so the bytes match what the app writes.
"""

from __future__ import annotations

import pathlib
import subprocess

from Scripts.Quality import repository_tool

# The tool takes its paths as arguments; a long list is split to stay under the argument limit.
BATCH = 500


def convert_json_files(paths: list[pathlib.Path]) -> None:
    """Writes `<stem>.plist` beside each JSON file in `paths`, in the canonical form."""
    for start in range(0, len(paths), BATCH):
        batch = paths[start : start + BATCH]
        result = subprocess.run(
            [str(repository_tool.binary()), "to-plist", *map(str, batch)],
            capture_output=True,
            check=False,
            text=True,
        )
        if result.returncode:
            raise repository_tool.ToolError(
                f"{repository_tool.PRODUCT} to-plist exited {result.returncode}: "
                f"{result.stderr.strip()}"
            )
