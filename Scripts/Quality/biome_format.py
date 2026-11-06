"""Format JSON text the way `biome.json` formats the repository's JSON files."""

from __future__ import annotations

import pathlib
import subprocess
import tempfile

from Scripts.Quality.biome_binary import BiomeBinaryError, command, resolve

ROOT = pathlib.Path(__file__).resolve().parents[2]


class BiomeError(OSError):
    """Biome is missing or refused the text."""


def format_json(texts: dict[pathlib.Path, str]) -> dict[pathlib.Path, str]:
    """Returns each text as Biome formats it; a key only gives the file's suffix."""
    if not texts:
        return {}
    with tempfile.TemporaryDirectory() as directory:
        staged = {
            path: pathlib.Path(directory) / f"{index}{path.suffix or '.json'}"
            for index, path in enumerate(texts)
        }
        for path, text in texts.items():
            staged[path].write_text(text, encoding="utf-8")
        try:
            binary = resolve(ROOT)
        except BiomeBinaryError as error:
            raise BiomeError(str(error)) from error
        try:
            result = subprocess.run(
                [
                    *command(binary),
                    "format",
                    "--write",
                    f"--config-path={ROOT / 'biome.json'}",
                    "--vcs-enabled=false",
                    directory,
                ],
                capture_output=True,
                check=False,
                text=True,
            )
        except FileNotFoundError as error:
            raise BiomeError(
                "bun is not installed; run: ./Scripts/ojd setup"
            ) from error
        if result.returncode:
            detail = result.stderr.strip() or result.stdout.strip()
            raise BiomeError(f"biome format failed: {detail}")
        return {
            path: temporary.read_text(encoding="utf-8")
            for path, temporary in staged.items()
        }
