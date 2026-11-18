from __future__ import annotations

import json
import re
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path

Version = tuple[int, int]

SWIFT_VERSION = re.compile(r"Swift version (\d+)\.(\d+)")
FOUNDATION_MODULE = (
    "System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule"
)
# SwiftUI attributes the sources use that an SDK may declare as macros. The macOS 27 SDK turns
# `@State` into a macro whose plugin ships only inside Xcode, so the Command Line Tools cannot
# expand it; the sources spell out what `@Entry` and the other macro-only APIs would generate.
SWIFTUI_MACROS_IN_USE = frozenset({"State"})
SWIFTUI_MODULES = (
    "System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule",
    "System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule",
)
EXTERNAL_MACRO = re.compile(
    r"\bmacro\s+(\w+)\([^)]*\)\s*=\s*#externalMacro\(\s*module:\s*\"(\w+)\""
)
SDK_ROOTS = (
    Path("/Library/Developer/CommandLineTools/SDKs"),
    *sorted(
        Path("/Applications").glob(
            "Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"
        )
    ),
)


def parse_version(text: str) -> Version | None:
    match = SWIFT_VERSION.search(text)
    return (int(match[1]), int(match[2])) if match else None


def compiler_version(swift: str) -> Version | None:
    try:
        result = subprocess.run(
            [swift, "--version"], capture_output=True, text=True, check=False
        )
    except OSError:
        return None
    return parse_version(result.stdout + result.stderr)


def interface_version(sdk: Path) -> Version | None:
    for interface in sorted((sdk / FOUNDATION_MODULE).glob("*.swiftinterface")):
        with interface.open(encoding="utf-8", errors="replace") as source:
            for line in source:
                if not line.startswith("//"):
                    break
                if "swift-compiler-version" in line:
                    return parse_version(line)
    return None


def toolchain_plugins(swift: str) -> Path | None:
    try:
        result = subprocess.run(
            [swift, "-print-target-info"], capture_output=True, text=True, check=False
        )
        resources = json.loads(result.stdout)["paths"]["runtimeResourcePath"]
    except (OSError, ValueError, KeyError, TypeError):
        return None
    return Path(resources) / "host" / "plugins"


def macro_modules(sdk: Path) -> dict[str, str]:
    modules: dict[str, str] = {}
    for module in SWIFTUI_MODULES:
        for interface in sorted((sdk / module).glob("*.swiftinterface"))[:1]:
            text = interface.read_text(encoding="utf-8", errors="replace")
            for name, plugin in EXTERNAL_MACRO.findall(text):
                modules.setdefault(name, plugin)
    return modules


def unexpandable_macros(sdk: Path, plugins: Path) -> list[str]:
    # The driver searches the toolchain's plugins and those of the platform that holds the SDK.
    folders = (
        plugins,
        sdk / ".." / ".." / "usr" / "lib" / "swift" / "host" / "plugins",
    )
    return sorted(
        name
        for name, module in macro_modules(sdk).items()
        if name in SWIFTUI_MACROS_IN_USE
        and not any((folder / f"lib{module}.dylib").exists() for folder in folders)
    )


def installed_sdks(roots: Iterable[Path] = SDK_ROOTS) -> list[Path]:
    found: dict[Path, None] = {}
    for root in roots:
        for sdk in sorted(root.glob("MacOSX*.sdk")):
            found.setdefault(sdk.resolve(), None)
    return list(found)


def readable(compiler: Version, sdk: Path, plugins: Path | None = None) -> bool:
    version = interface_version(sdk)
    if version is None or version > compiler:
        return False
    return plugins is None or not unexpandable_macros(sdk, plugins)


def select_sdk(
    compiler: Version,
    preferred: Path,
    candidates: Iterable[Path],
    plugins: Path | None = None,
) -> Path | None:
    if readable(compiler, preferred, plugins):
        return preferred
    fitting = [
        (version, sdk)
        for sdk in candidates
        if (version := interface_version(sdk)) is not None
        and readable(compiler, sdk, plugins)
    ]
    return max(fitting, key=lambda item: item[0])[1] if fitting else None


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "usage: swift_sdk.py <swift> <preferred-sdk> <explicit 0|1> [sdk-root...]",
            file=sys.stderr,
        )
        return 2
    swift, preferred, explicit = argv[0], Path(argv[1]), argv[2] == "1"
    roots = [Path(root) for root in argv[3:]] or SDK_ROOTS
    compiler = compiler_version(swift)
    if compiler is None:
        print(
            f"error: `{swift} --version` names no Swift version, so no SDK can be paired with it",
            file=sys.stderr,
        )
        return 1
    plugins = toolchain_plugins(swift)
    if explicit:
        if readable(compiler, preferred):
            missing = [] if plugins is None else unexpandable_macros(preferred, plugins)
            if not missing:
                print(preferred)
                return 0
            print(
                f"error: SDKROOT={preferred} declares SwiftUI macros {', '.join(missing)} "
                f"whose plugins {swift} lacks; unset SDKROOT, or select an Xcode with "
                "DEVELOPER_DIR",
                file=sys.stderr,
            )
            return 1
        print(
            f"error: SDKROOT={preferred} needs a newer Swift than {swift} "
            f"({compiler[0]}.{compiler[1]}); unset SDKROOT, or select the Xcode whose "
            "Swift .swift-version or newer",
            file=sys.stderr,
        )
        return 1
    sdk = select_sdk(compiler, preferred, installed_sdks(roots), plugins)
    if sdk is None:
        print(
            f"error: no installed macOS SDK can be read by Swift {compiler[0]}.{compiler[1]} "
            f"({swift}) with the SwiftUI macro plugins it has; select an Xcode whose Swift is "
            ".swift-version or newer",
            file=sys.stderr,
        )
        return 1
    if sdk != preferred:
        print(
            f"note: Swift {compiler[0]}.{compiler[1]} ({swift}) cannot build with "
            f"{preferred}; using {sdk}",
            file=sys.stderr,
        )
    print(sdk)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
