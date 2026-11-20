"""Writes compile_commands.json for clang-tidy and clangd, which SwiftPM does not write.

The database holds one entry per C, C++, and Objective-C source of each SwiftPM Clang target,
then the entries xmake writes for each tracked xmake project. A nested xmake.lua is skipped,
because its parent project `includes` it.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENT_TARGET = "13.0"


def run(arguments: list[str], root: Path) -> str:
    try:
        return subprocess.run(
            arguments, cwd=root, capture_output=True, text=True, check=True
        ).stdout
    except subprocess.CalledProcessError as error:
        # The output names the cause, such as a package xmake cannot find.
        sys.stderr.write(error.stdout + error.stderr)
        raise


def language_flags(source: str, standard: str) -> list[str]:
    extension = PurePosixPath(source).suffix
    if extension == ".c":
        return ["clang", "-std=c17"]
    if extension == ".m":
        return ["clang", "-fobjc-arc"]
    if extension == ".mm":
        return ["clang++", f"-std={standard}", "-fobjc-arc"]
    return ["clang++", f"-std={standard}"]


def clang_target_entries(
    root: Path, description: dict[str, object], resources: str, sdk: str
) -> list[dict[str, object]]:
    standard = description.get("cxx_language_standard") or "c++20"
    targets = [
        target
        for target in description.get("targets") or []
        if target.get("module_type") == "ClangTarget"
    ]
    # <swift/bridging> lives in the toolchain's usr/include, beside usr/lib/swift.
    toolchain_include = str((Path(resources) / ".." / ".." / "include").resolve())
    common = [
        "-isystem",
        toolchain_include,
        f"-mmacosx-version-min={DEPLOYMENT_TARGET}",
    ]
    for target in targets:
        common += ["-I", f"{root}/{target['path']}/include"]
    if sdk:
        common = ["-isysroot", sdk, *common]
    entries: list[dict[str, object]] = []
    for target in targets:
        for source in target.get("sources") or []:
            file = f"{root}/{target['path']}/{source}"
            arguments = [*language_flags(source, standard), *common, "-c", file]
            entries.append(
                {"directory": str(root), "file": file, "arguments": arguments}
            )
    return entries


def top_level_projects(manifests: list[str]) -> list[str]:
    projects = [str(PurePosixPath(manifest).parent) for manifest in manifests]
    projects = ["" if project == "." else project for project in projects]
    return [
        project
        for project in projects
        if not any(
            other != project and (other == "" or project.startswith(other + "/"))
            for other in projects
        )
    ]


def xmake_entries(root: Path) -> list[dict[str, object]]:
    manifests = run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--"]
        + ["xmake.lua", "*/xmake.lua"],
        root,
    ).split()
    entries: list[dict[str, object]] = []
    for project in top_level_projects(manifests):
        with tempfile.TemporaryDirectory() as output:
            run(
                ["xmake", "project", "-q", "-y", "-P", str(root / project)]
                + ["-k", "compile_commands", output],
                root,
            )
            database = Path(output) / "compile_commands.json"
            entries += json.loads(database.read_text(encoding="utf-8"))
    return entries


def main(arguments: list[str]) -> int:
    root = Path(arguments[0]) if arguments else ROOT
    description = json.loads(
        run(["swift", "package", "describe", "--type", "json"], root)
    )
    info = json.loads(run(["swift", "-print-target-info"], root))
    resources = info.get("paths", {}).get("runtimeResourcePath", "")
    sdk = run(["xcrun", "--show-sdk-path"], root).strip()
    entries = clang_target_entries(root, description, resources, sdk)
    entries += xmake_entries(root)
    (root / "compile_commands.json").write_text(
        json.dumps(entries, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
