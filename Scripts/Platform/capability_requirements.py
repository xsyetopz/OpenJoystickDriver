"""Command route capability requirements."""

from __future__ import annotations

from .capability_model import Capability


def requirements_for(argv: list[str]) -> tuple[Capability, ...]:
    route = tuple(argv)
    if any(argument in {"-h", "--help", "help"} for argument in route[1:]):
        return ()
    if route[:2] == ("catalog", "regenerate") and len(route) >= 3:
        return (Capability.SCHEMA_PYTHON,)
    if route == ("check", "profiles"):
        return (Capability.SCHEMA_PYTHON,)
    if route == ("check", "schemas"):
        return (
            Capability.SCHEMA_PYTHON,
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
        )
    if route == ("check", "tools"):
        return (Capability.XMAKE, Capability.PKG_CONFIG, Capability.SDL3)
    if route == ("check", "driverkit"):
        return (
            Capability.SCHEMA_PYTHON,
            Capability.SWIFT_TOOLCHAIN,
            Capability.SWIFTLINT,
            Capability.FULL_XCODE,
        )
    if route[:2] == ("driverkit", "generate") and len(route) <= 3:
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route == ("build", "dev") or route in {
        ("build", "install", "dev"),
        ("build", "install-fast", "dev"),
    }:
        return (
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
            Capability.DEVELOPMENT_SIGNING,
        )
    if route == ("build", "dext"):
        return (
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
            Capability.DEVELOPMENT_SIGNING,
        )
    if route == ("build", "release") or route == ("build", "install", "release"):
        return (
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
            Capability.RELEASE_SIGNING,
        )
    if route == ("package", "tester") or (
        route[:2] in {("release", "package"), ("release", "install-local")}
        and len(route) <= 3
    ):
        return (
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
            Capability.RELEASE_SIGNING,
            Capability.NOTARIZATION,
        )
    if route[:2] == ("release", "notarize") and (
        len(route) < 3 or route[2] != "store-credentials"
    ):
        return (
            Capability.FULL_XCODE,
            Capability.RELEASE_SIGNING,
            Capability.NOTARIZATION,
        )
    if route[:3] == ("release", "notarize", "store-credentials"):
        return (Capability.FULL_XCODE, Capability.RELEASE_SIGNING)
    if route[:2] == ("docs", "export-external-issues"):
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] == ("github", "ensure-auth"):
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] == ("signing", "export-github-secrets") and "--apply" in route:
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] in {
        ("diagnose", "sdl3"),
        ("diagnose", "sdl3-gamecontroller"),
        ("diagnose", "sdl3-hidapi-x360"),
        ("diagnose", "backends"),
    }:
        base = (
            Capability.FULL_XCODE,
            Capability.XMAKE,
            Capability.PKG_CONFIG,
            Capability.SDL3,
        )
        return (
            (Capability.SWIFT_TOOLCHAIN, *base)
            if route[:2] == ("diagnose", "backends")
            else base
        )
    if route[:2] in {("diagnose", "record"), ("diagnose", "gamecontroller")}:
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route[:2] == ("diagnose", "rumble-motors"):
        return (
            Capability.SWIFT_TOOLCHAIN,
            Capability.FULL_XCODE,
            Capability.DEVELOPMENT_SIGNING,
        )
    if route == ("test", "parsers-macos14"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route[:2] == ("hooks", "install") or route[:2] == ("hooks", "validate"):
        return (Capability.LEFTHOOK,)
    if route == ("setup",):
        return (
            Capability.JUST,
            Capability.LEFTHOOK,
            Capability.RUFF,
            Capability.PYRIGHT,
            Capability.SHELLCHECK,
            Capability.SWIFTLINT,
        )
    return ()
