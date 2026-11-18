"""Reports what SwiftLint and swift-format cannot see in the Swift sources and the manifest.

The package keeps Swift 6 mode, the upcoming features, strict memory safety, and warnings as
errors on every target, and the Xcode project builds against Config/Base.xcconfig with the same
flags. Tests use Swift Testing outside UI test targets, and a suppression covers one declaration
rather than the rest of a file.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS_VERSION = "6.4"
BASE_XCCONFIG = "Config/Base.xcconfig"
STRICT_SETTINGS = (
    "enableUpcomingFeature:ExistentialAny",
    "enableUpcomingFeature:InternalImportsByDefault",
    "enableUpcomingFeature:MemberImportVisibility",
    "enableUpcomingFeature:InferIsolatedConformances",
    "enableUpcomingFeature:NonisolatedNonsendingByDefault",
    "enableUpcomingFeature:ImmutableWeakCaptures",
    "strictMemorySafety",
    "treatAllWarnings:error",
)
UNCHECKED_TARGETS = frozenset({"system", "binary", "plugin"})
FOREIGN_TOOLS = {
    "Podfile": "CocoaPods: move each pod to a SwiftPM dependency in Package.swift",
    "Cartfile": "Carthage: move each framework to a SwiftPM dependency in Package.swift",
    ".swiftformat": "SwiftFormat: swift-format and .swift-format own the layout",
}
XCTEST_IMPORT = re.compile(r"(?m)^\s*(?:@\w+\s+)*import\s+(?:\w+\s+)?XCTest\b")
DISABLE = "swiftlint:disable"
ENABLE = "swiftlint:enable"


def setting_names(target: dict[str, object]) -> set[str]:
    names: set[str] = set()
    for setting in target.get("settings") or []:
        kind = setting.get("kind") if isinstance(setting, dict) else None
        for key, value in (kind or {}).items():
            argument = value.get("_0") if isinstance(value, dict) else None
            names.add(f"{key}:{argument}" if isinstance(argument, str) else key)
    return names


def manifest_problems(package: dict[str, object]) -> list[str]:
    problems: list[str] = []
    tools = (package.get("toolsVersion") or {}).get("_version", "")
    if not tools.startswith(TOOLS_VERSION):
        problems.append(
            f"Package.swift: swift-tools-version is {tools}; use {TOOLS_VERSION}"
        )
    modes = package.get("swiftLanguageModes") or package.get("swiftLanguageVersions")
    if modes != ["6"]:
        problems.append(
            f"Package.swift: the language modes are {modes}; use [.v6] alone"
        )
    for target in package.get("targets") or []:
        if target.get("type") in UNCHECKED_TARGETS:
            continue
        names = setting_names(target)
        missing = [setting for setting in STRICT_SETTINGS if setting not in names]
        if missing:
            problems.append(
                f"Package.swift: target {target.get('name')} lacks {', '.join(missing)}; "
                "keep the settings loop last in the manifest"
            )
        if "unsafeFlags" in names:
            problems.append(
                f"Package.swift: target {target.get('name')} uses unsafeFlags, which keeps "
                "other packages from depending on it"
            )
    return problems


def is_ui_test(path: str) -> bool:
    return any(part.endswith(("UITests", "UITest")) for part in path.split("/")[:-1])


def directive(line: str) -> str:
    start = line.find("//")
    return "" if start < 0 else line[start:].lstrip("/ ")


def suppressions(text: str) -> list[str]:
    directives = [directive(line) for line in text.split("\n")]
    found: list[str] = []
    for index, current in enumerate(directives):
        if current.startswith("swift-format-ignore-file"):
            found.append(
                f"{index + 1}: swift-format-ignore-file; ignore the one declaration instead"
            )
        if not current.startswith(DISABLE) or current[len(DISABLE) :].startswith(":"):
            continue
        rules = []
        for word in current[len(DISABLE) :].split():
            if word.startswith("//"):
                break
            rules.append(word)
        reenabled = any(
            later.startswith(ENABLE) and set(rules) <= set(later[len(ENABLE) :].split())
            for later in directives[index + 1 :]
        )
        if not reenabled:
            found.append(
                f"{index + 1}: swiftlint:disable without a matching swiftlint:enable; use "
                "swiftlint:disable:next"
            )
    return found


def source_problems(path: str, text: str) -> list[str]:
    problems: list[str] = []
    if not is_ui_test(path) and XCTEST_IMPORT.search(text):
        problems.append(
            f"{path}: imports XCTest outside a *UITests target; use Swift Testing"
        )
    problems += [f"{path}:{finding}" for finding in suppressions(text)]
    return problems


def project_problems(path: str, pbxproj: str) -> list[str]:
    problems: list[str] = []
    if BASE_XCCONFIG not in pbxproj:
        problems.append(
            f"{path}: set {BASE_XCCONFIG} as the base configuration of the project's "
            "Debug and Release"
        )
    overrides: set[str] = set()
    for line in pbxproj.splitlines():
        setting = line.strip()
        if setting.startswith("SWIFT_VERSION = ") and not setting.startswith(
            "SWIFT_VERSION = 6"
        ):
            overrides.add(f"{setting} keeps the target out of Swift 6 mode")
        if setting.startswith("OTHER_SWIFT_FLAGS = ") and "$(inherited)" not in setting:
            overrides.add(
                "OTHER_SWIFT_FLAGS without $(inherited) drops the upcoming features"
            )
    return problems + [
        f"{path}: {override}; remove it" for override in sorted(overrides)
    ]


def tracked_swift_files(root: Path) -> list[str]:
    output = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "*.swift",
        ],
        cwd=root,
        capture_output=True,
        check=True,
    ).stdout
    return sorted(path for path in output.decode().split("\0") if path)


def dump_package(root: Path) -> dict[str, object]:
    output = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return json.loads(output)


def scan(root: Path, swift_files: Iterable[str]) -> list[str]:
    problems: list[str] = []
    if (root / "Package.swift").exists():
        problems += manifest_problems(dump_package(root))
    for path in swift_files:
        file = root / path
        if file.is_file():
            problems += source_problems(path, file.read_text(encoding="utf-8"))
    for name, problem in sorted(FOREIGN_TOOLS.items()):
        if (root / name).exists():
            problems.append(f"{name}: {problem}")
    for project in sorted(root.glob("*.xcodeproj")):
        pbxproj = project / "project.pbxproj"
        if pbxproj.is_file():
            relative = str(pbxproj.relative_to(root))
            problems += project_problems(relative, pbxproj.read_text(encoding="utf-8"))
    return problems


def main(arguments: list[str]) -> int:
    root = Path(arguments[0]) if arguments else ROOT
    problems = scan(root, tracked_swift_files(root))
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
