from __future__ import annotations

import json
import subprocess
from functools import cache
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "OJDRepositoryTool"
PROBLEM_STATUS = 1


def swift_command(*arguments: str) -> list[str]:
    return [str(ROOT / "Scripts/with-env.sh"), "swift", *arguments]


class ToolError(Exception): ...


def build(product: str) -> Path:
    try:
        subprocess.run(
            swift_command("build", "--product", product),
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        bin_path = subprocess.run(
            swift_command("build", "--show-bin-path"),
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        raise ToolError(f"cannot build {product}: {detail}") from error
    built = Path(bin_path.stdout.strip()) / product
    if not built.is_file():
        raise ToolError(f"{product} was not built at {built}")
    return built


@cache
def binary() -> Path:
    return build(PRODUCT)


def problems(arguments: list[str]) -> list[dict[str, str]]:
    result = subprocess.run(
        [str(binary()), *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode not in {0, PROBLEM_STATUS}:
        raise ToolError(
            f"{PRODUCT} {' '.join(arguments)} exited {result.returncode}: "
            f"{result.stderr.strip()}"
        )
    try:
        found = [json.loads(line) for line in result.stdout.splitlines()]
    except json.JSONDecodeError as error:
        raise ToolError(
            f"{PRODUCT} printed a line that is not JSON: {error}"
        ) from error
    for line in found:
        if not isinstance(line, dict) or not {"file", "code", "message"} <= line.keys():
            raise ToolError(f"{PRODUCT} printed a line that is not a problem: {line}")
    if (result.returncode == PROBLEM_STATUS) != bool(found):
        raise ToolError(
            f"{PRODUCT} {' '.join(arguments)} exited {result.returncode} "
            f"with {len(found)} problem line(s)"
        )
    return found


def describe(problem: dict[str, str]) -> str:
    path = Path(problem["file"])
    shown = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
    return f"{problem['code']}: {shown}: {problem['message']}"


def check(arguments: list[str]) -> None:
    found = problems(arguments)
    if found:
        raise ToolError("\n".join(describe(problem) for problem in found))


def document(arguments: list[str]) -> dict[str, Any]:
    result = subprocess.run(
        [str(binary()), *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ToolError(
            f"{PRODUCT} {' '.join(arguments)} exited {result.returncode}: "
            f"{result.stderr.strip()}"
        )
    try:
        found = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ToolError(f"{PRODUCT} printed text that is not JSON: {error}") from error
    if not isinstance(found, dict):
        raise ToolError(f"{PRODUCT} {' '.join(arguments)} did not print an object")
    return found


@cache
def facts() -> dict[str, Any]:
    return document(["facts"])


def api_version() -> str:
    return str(facts()["apiVersion"])


def schema_base() -> str:
    return str(facts()["schemaBase"])


def command_line_exit_statuses() -> frozenset[int]:
    return frozenset(int(status) for status in facts()["commandLineExitStatuses"])


def domain_code_prefixes() -> dict[str, str]:
    prefixes = facts()["domainCodePrefixes"]
    return {str(name): str(prefix) for name, prefix in prefixes.items()}


def domain_areas() -> dict[str, str]:
    areas = facts()["domainAreas"]
    return {str(name): str(area) for name, area in areas.items()}


def kebab(values: list[str]) -> dict[str, str]:
    return {str(key): str(value) for key, value in document(["kebab", *values]).items()}
