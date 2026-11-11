from __future__ import annotations

import pathlib
import subprocess

from Scripts.Quality import repository_tool

BATCH = 500


def convert_json_files(paths: list[pathlib.Path]) -> None:
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
