from __future__ import annotations

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


def installed_sdks(roots: Iterable[Path] = SDK_ROOTS) -> list[Path]:
    found: dict[Path, None] = {}
    for root in roots:
        for sdk in sorted(root.glob("MacOSX*.sdk")):
            found.setdefault(sdk.resolve(), None)
    return list(found)


def readable(compiler: Version, sdk: Path) -> bool:
    version = interface_version(sdk)
    return version is not None and version <= compiler


def select_sdk(
    compiler: Version, preferred: Path, candidates: Iterable[Path]
) -> Path | None:
    if readable(compiler, preferred):
        return preferred
    versions = [(interface_version(sdk), sdk) for sdk in candidates]
    fitting = [
        (version, sdk)
        for version, sdk in versions
        if version is not None and version <= compiler
    ]
    return max(fitting, key=lambda item: item[0])[1] if fitting else None


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "usage: swift_sdk.py <swift> <preferred-sdk> <explicit 0|1>",
            file=sys.stderr,
        )
        return 2
    swift, preferred, explicit = argv[0], Path(argv[1]), argv[2] == "1"
    compiler = compiler_version(swift)
    if compiler is None:
        print(
            f"error: `{swift} --version` names no Swift version, so no SDK can be paired with it",
            file=sys.stderr,
        )
        return 1
    if explicit:
        if readable(compiler, preferred):
            print(preferred)
            return 0
        print(
            f"error: SDKROOT={preferred} needs a newer Swift than {swift} "
            f"({compiler[0]}.{compiler[1]}); unset SDKROOT, or select the Xcode whose "
            "Swift .swift-version or newer",
            file=sys.stderr,
        )
        return 1
    sdk = select_sdk(compiler, preferred, installed_sdks())
    if sdk is None:
        print(
            f"error: no installed macOS SDK can be read by Swift {compiler[0]}.{compiler[1]} "
            f"({swift}); select an Xcode whose Swift is .swift-version or newer",
            file=sys.stderr,
        )
        return 1
    if sdk != preferred:
        print(
            f"note: Swift {compiler[0]}.{compiler[1]} cannot read {preferred}; using {sdk}",
            file=sys.stderr,
        )
    print(sdk)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
