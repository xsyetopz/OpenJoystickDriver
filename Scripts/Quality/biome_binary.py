"""Find the pinned Biome binary for one checkout.

The binary is `node_modules/.bin/biome` of the checkout's top level, else of the main
worktree (a linked worktree has no `bun install` of its own). Its version must equal the
`@biomejs/biome` pin in the checkout's `package.json`. A Biome on `PATH` is never used.
The binary is a Node script, which `command` runs with Bun: the repository installs no Node.
Run as `python3 -m Scripts.Quality.biome_binary TOPLEVEL`, it prints the binary path.
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

from Scripts.Command.execution import main_checkout_dir

BINARY = pathlib.Path("node_modules/.bin/biome")


class BiomeBinaryError(OSError):
    """No usable pinned Biome binary exists."""


def pinned_version(toplevel: pathlib.Path) -> str:
    package = json.loads((toplevel / "package.json").read_text(encoding="utf-8"))
    return str(package["devDependencies"]["@biomejs/biome"])


def command(binary: pathlib.Path) -> list[str]:
    return ["bun", "run", str(binary)]


def installed_version(binary: pathlib.Path) -> str:
    result = subprocess.run(
        [*command(binary), "--version"], capture_output=True, check=False, text=True
    )
    match = re.search(r"\d+\.\d+\.\d+\S*", result.stdout)
    if result.returncode or match is None:
        raise BiomeBinaryError(f"{binary} --version failed: {result.stderr.strip()}")
    return match.group(0)


def resolve(toplevel: pathlib.Path, main: pathlib.Path | None = None) -> pathlib.Path:
    """Returns the pinned binary, or raises BiomeBinaryError with what to run."""
    if main is None:
        try:
            main = main_checkout_dir(toplevel)
        except subprocess.CalledProcessError as error:
            raise BiomeBinaryError(
                f"{toplevel} is not in a Git checkout: {error.stderr.strip()}"
            ) from error
    candidates = [toplevel / BINARY]
    if main.resolve() != toplevel.resolve():
        candidates.append(main / BINARY)
    for binary in candidates:
        if not binary.is_file():
            continue
        pin = pinned_version(toplevel)
        version = installed_version(binary)
        if version != pin:
            raise BiomeBinaryError(
                f"{binary} is Biome {version} but package.json pins {pin}; "
                f"run bun install in {binary.parents[2]}"
            )
        return binary
    searched = ", ".join(str(binary) for binary in candidates)
    raise BiomeBinaryError(
        f"the pinned Biome is not installed (looked for {searched}); "
        f"run bun install in {main}"
    )


if __name__ == "__main__":
    try:
        print(resolve(pathlib.Path(sys.argv[1])))
    except (BiomeBinaryError, OSError, KeyError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
