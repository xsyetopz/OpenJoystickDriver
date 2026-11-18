from __future__ import annotations

import os
import re
import shlex
import sys
from collections.abc import Mapping
from pathlib import Path

SIGNING_KEYS = frozenset(
    {
        "CODESIGN_IDENTITY",
        "DEVELOPMENT_TEAM",
        "DEXT_PROVISIONING_PROFILE",
        "GUI_PROVISIONING_PROFILE",
        "OJD_USE_LOCAL_SWIFTERKIT",
    }
)
NOTARIZATION_KEYS = frozenset(
    {"NOTARIZE_APPLE_ID", "NOTARIZE_PASSWORD", "NOTARIZE_KEYCHAIN_PROFILE"}
)
KEYS = {".env.dev": SIGNING_KEYS, ".env.release": SIGNING_KEYS | NOTARIZATION_KEYS}

_REFERENCE = re.compile(r"\$(?:\{(\w+)\}|(\w+))")


class EnvFileError(ValueError):
    pass


def _expand(value: str, environ: Mapping[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        name = match.group(1) or match.group(2)
        return environ.get(name, match.group(0))

    return _REFERENCE.sub(replace, value)


def allowed_keys(path: Path) -> frozenset[str]:
    try:
        return KEYS[path.name]
    except KeyError:
        raise EnvFileError(
            f"{path.name} is not an environment file (expected .env.dev or .env.release)"
        ) from None


def read(path: Path, environ: Mapping[str, str] | None = None) -> dict[str, str]:
    keys = allowed_keys(path)
    if not path.is_file():
        return {}
    environ = os.environ if environ is None else environ
    values: dict[str, str] = {}
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or not key:
            raise EnvFileError(f"{path}:{number}: expected KEY=value")
        if key not in keys:
            raise EnvFileError(
                f"{path}:{number}: {key} is not a key of {path.name}; remove the line. "
                f"{path.name} takes: {', '.join(sorted(keys))}"
            )
        try:
            words = shlex.split(raw_value, comments=True, posix=True)
        except ValueError as error:
            raise EnvFileError(f"{path}:{number}: {error}") from None
        if len(words) > 1:
            raise EnvFileError(f"{path}:{number}: the value of {key} must be one word")
        values[key] = _expand(words[0], environ) if words else ""
    return values


def update(path: Path, key: str, value: str) -> None:
    if key not in allowed_keys(path):
        raise EnvFileError(f"{key} is not a key of {path.name}")
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    assignment = f'{key}="{value}"'
    replaced = False
    result: list[str] = []
    for line in lines:
        if line.startswith(f"{key}="):
            if not replaced:
                result.append(assignment)
                replaced = True
        else:
            result.append(line)
    if not replaced:
        if result and result[-1]:
            result.append("")
        result.append(assignment)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text("\n".join(result) + "\n", encoding="utf-8")
    os.replace(temporary, path)


USAGE = "usage: env_file.py read <file> | env_file.py update <file> <key> <value>"


def main(argv: list[str]) -> int:
    try:
        match argv:
            case ["read", path]:
                for key, value in read(Path(path)).items():
                    sys.stdout.buffer.write(
                        key.encode() + b"\0" + value.encode() + b"\0"
                    )
                return 0
            case ["update", path, key, value]:
                update(Path(path), key, value)
                return 0
            case _:
                print(USAGE, file=sys.stderr)
                return 2
    except EnvFileError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
