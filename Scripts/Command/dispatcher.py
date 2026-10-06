"""OpenJoystickDriver repository command dispatcher."""

from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

from Scripts.Platform.capabilities import CapabilityError, Resolver, requirements_for

SCRIPT_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = SCRIPT_DIR.parent
ENVIRONMENT = SCRIPT_DIR / "Platform/environment.sh"
SCHEMA_PYTHON = PROJECT_DIR / ".build" / "schema-validator" / "bin" / "python"
APP_INFO = PROJECT_DIR / "Sources/OpenJoystickDriver/App/Info.plist"

HELP_DESCRIPTION = """OpenJoystickDriver repository dev helper.

This is the repository dispatcher, not the product `ojd`. The shipped CLI is
the app binary, run as `ojd` once installed.

"""


def die(message: str) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(2)


COMMAND_HELP = """Commands:
  build dev                   Build + sign app bundle into `.build/` (no dext)
  build release               Build + sign app bundle for release (no dext)
  build dext                  Build DriverKit `.dext` and embed into `.build/` app
  build install dev|release   Full rebuild and install
  build install-fast dev      App-only rebuild and install (keeps installed sysext)
  driverkit generate [path]   Generate a fresh SwifterKit DriverKit project
  package tester               Build a private, shareable Developer ID DMG
  release bump-version <version>
                              Update release version references
  release package [version]  Build, notarize, staple, and package a release DMG
  release install-local [version]
                              Package and install the release app locally
  release notarize <command> Run release notarization operations

  env audit                   Validate the single-file env contract without printing values
  docs export-external-issues Refresh archived GitHub issue and pull-request evidence
  docs build-wiki <dir>       Convert wiki/ into GitHub wiki pages in an empty directory
  docs publish-wiki [--dry-run] Publish wiki/ to the GitHub wiki (--dry-run shows the diff only)
  github ensure-auth          Install and authenticate GitHub CLI when needed
  signing install-profiles    Copy profiles from ~/Documents/Profiles into MobileDevice
  signing configure            Generate .env.dev + .env.release from Keychain + profiles
  signing doctor               Diagnose common cert/profile mismatch errors (safe output)
  signing audit [paths...]     Audit profiles without leaking identifiers
  signing cert-info <cer>      Show safe-ish .cer info (Team ID = Subject OU)
  signing profile-info <pp>    Show safe-ish profile embedded cert info
  signing import-embedded <pp> Import embedded cert from a profile into Keychain
  signing ci-release-setup     Import GitHub Actions release secrets (CI only)
  signing export-github-secrets
                               Write/import GitHub Actions release secrets

  diagnose dext               Run dext diagnostics (activation, codesign, IORegistry, application service connection)
  diagnose record <json>      Validate a record or probe through the USB DEXT
  diagnose usb-passive <vid> <pid>
                              Print an authorized device's USB descriptor facts (debug build)
  diagnose sdl3 [--seconds N] Run SDL3 probe against the virtual device
  diagnose sdl3-gamecontroller [--seconds N]
                              Run SDL3 through GameController/MFI and test rumble
  diagnose sdl3-hidapi-x360 [--seconds N]
                              Run SDL3 through Xbox 360 HIDAPI and test rumble
  diagnose gamecontroller     Run GameController.framework probe
  diagnose backends           Run current backend acceptance loop
  diagnose rumble-motors <vid> <pid> [intensity] [duration-ms]
                              Identify physical rumble actuators interactively
  repair stale-dext           Kill stale DriverKit process copies after upgrade
  repair swiftpm-module-cache Clean SwiftPM build products after toolchain/target changes
  catalog regenerate --check Verify the runtime catalog against pinned sources and overrides
  catalog regenerate --write Rebuild the runtime catalog from pinned sources and overrides
  catalog xpad [options]      Generate review-only records from a pinned Linux xpad.c
  errors regenerate --check   Verify the error code schema enum and wiki table against the catalog
  errors regenerate --write   Rebuild the error code schema enum and wiki table from the catalog
  check profiles              Check canonical controller records
  check schemas               Validate canonical schemas and a live support report
  check driverkit             Verify generated DriverKit reproducibility and build
  check tools                 Build the SDL gamepad probe
  test parsers-macos14        Run focused parser regressions without Swift Testing
  launch sdl-gamecontroller <app>
                              Launch an SDL app through GameController/MFI rumble route

  hooks install|validate      Install or validate repository Git hooks
  setup                       Install required command runner and hooks

Examples:
  ./Scripts/ojd signing install-profiles
  ./Scripts/ojd signing configure
  ./Scripts/ojd diagnose record /tmp/controller.json --validate-only
  ./Scripts/ojd catalog xpad --github-ref master --output-dir /tmp/ojd-xpad
  ./Scripts/ojd build install-fast dev
  ./Scripts/ojd release bump-version 0.1.0-rc.2

Notes:
  - Most commands expect the app to be installed to /Applications.
  - DriverKit upgrades can require a reboot; use build install-fast while streaming.
"""


def project_version() -> str:
    with APP_INFO.open("rb") as handle:
        return str(plistlib.load(handle)["CFBundleShortVersionString"])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="./Scripts/ojd",
        usage="./Scripts/ojd [-h] [--version] <command> [args]",
        description=HELP_DESCRIPTION + COMMAND_HELP,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"OpenJoystickDriver repository dispatcher {project_version()}",
    )
    return parser


def usage() -> None:
    build_parser().print_help()


def package_usage() -> None:
    print("""OpenJoystickDriver packaging

Usage:
  ./Scripts/ojd package <subcommand> [args]

Subcommands:
  tester                      Build a private notarized Developer ID DMG
  release [version]           Build, notarize, staple, and package a release DMG

The tester path notarizes and staples without installing or publishing. The release path is
also available as ./Scripts/ojd release package [version].""")


def require(
    command: str,
    args: list[str],
    *,
    count: int | None = None,
    maximum: int | None = None,
) -> None:
    if count is not None and len(args) != count:
        die(
            f"{command} requires exactly one argument"
            if count == 1
            else f"{command} does not accept arguments"
        )
    if maximum is not None and len(args) > maximum:
        die(f"{command} accepts at most one argument")


def env_with(overrides: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.update(overrides or {})
    return env


def exec_target(
    relative: str,
    args: list[str],
    *,
    env: dict[str, str] | None = None,
    python: bool = False,
    schema_python: bool = False,
) -> NoReturn:
    path = SCRIPT_DIR / relative
    python_executable = (
        str(SCHEMA_PYTHON)
        if schema_python and SCHEMA_PYTHON.is_file()
        else sys.executable
    )
    module = f"Scripts.{relative.removesuffix('.py').replace('/', '.')}"
    command = (
        [python_executable, "-m", module, *args]
        if python
        else ["/usr/bin/env", "bash", str(path), *args]
    )
    os.execvpe(command[0], command, env_with(env))


def exec_python_with_environment(relative: str, args: list[str]) -> NoReturn:
    module = f"Scripts.{relative.removesuffix('.py').replace('/', '.')}"
    command = [
        "/bin/bash",
        "-c",
        'source "$1"; cd "$2"; exec "$3" -m "$4" "${@:5}"',
        "ojd",
        str(ENVIRONMENT),
        str(PROJECT_DIR),
        sys.executable,
        module,
        *args,
    ]
    os.execvpe(command[0], command, env_with({"OJD_ENV": "release"}))


from .execution import (
    repair_swiftpm_cache,
    run_commands,
    run_record,
    run_usb_passive,
)


def dispatch(argv: list[str]) -> int:
    command = argv[0] if argv else ""
    rest = argv[1:]
    if command.startswith("-"):
        build_parser().parse_args(argv[:1])
    match command:
        case "" | "help":
            usage()
            return 0
        case "build":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "-h", "--help", "help"}:
                exec_target("Build/build.sh", ["help"])
            if sub in {"dev", "dext", "release"}:
                require(f"build {sub}", tail, count=0)
                exec_target(
                    "Build/build.sh",
                    ["build", sub],
                    env={"OJD_ENV": "release"} if sub == "release" else None,
                )
            if sub in {"install", "install-fast"}:
                config, tail = (tail[0], tail[1:]) if tail else ("", [])
                if sub == "install-fast" and config != "dev":
                    die(f"Unknown: build install-fast {config} (expected: dev)")
                if sub == "install" and config not in {"dev", "release"}:
                    die(f"Unknown: build install {config} (expected: dev | release)")
                require(f"build {sub} {config}", tail, count=0)
                exec_target(
                    "Build/install.sh",
                    [sub, config],
                    env={"OJD_ENV": "release"} if config == "release" else None,
                )
            die(
                f"Unknown: build {sub} (expected: dev | dext | release | install | install-fast)"
            )
        case "driverkit":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub != "generate":
                die(f"Unknown: driverkit {sub} (expected: generate)")
            require("driverkit generate", tail, maximum=1)
            exec_target("Build/driverkit.sh", [sub, *tail])
        case "env":
            if rest != ["audit"]:
                die(f"Unknown: env {rest[0] if rest else ''} (expected: audit)")
            exec_target("Quality/env_audit.py", [], python=True)
        case "docs":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub == "build-wiki":
                require("docs build-wiki", tail, count=1)
                exec_target("Documentation/wiki/build.py", tail, python=True)
            if sub == "publish-wiki":
                exec_target("Documentation/wiki/publish.py", tail, python=True)
            if rest != ["export-external-issues"]:
                die(
                    f"Unknown: docs {sub} "
                    "(expected: export-external-issues | build-wiki | publish-wiki)"
                )
            exec_target("Documentation/issues/export.py", [], python=True)
        case "github":
            if rest != ["ensure-auth"]:
                die(
                    f"Unknown: github {rest[0] if rest else ''} (expected: ensure-auth)"
                )
            return 0
        case "signing":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "-h", "--help", "help"}:
                exec_target("Signing/signing.sh", ["help"])
            if sub == "export-github-secrets":
                exec_target("Signing/export-github-secrets.sh", tail)
            if sub in {
                "install-profiles",
                "configure",
                "doctor",
                "audit",
                "cert-info",
                "profile-info",
                "import-embedded",
                "ci-release-setup",
            }:
                if sub in {"configure", "doctor", "ci-release-setup"}:
                    require(f"signing {sub}", tail, count=0)
                if sub == "install-profiles":
                    require(f"signing {sub}", tail, maximum=1)
                exec_target("Signing/signing.sh", [sub, *tail])
            die(
                f"Unknown: signing {sub} (expected: install-profiles | configure | doctor | audit | cert-info | profile-info | import-embedded | ci-release-setup | export-github-secrets)"
            )
        case "catalog":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub not in {"regenerate", "xpad"}:
                die(f"Unknown: catalog {sub} (expected: regenerate | xpad)")
            target = (
                "Catalog/generate_controller_catalog.py"
                if sub == "regenerate"
                else "Catalog/generate_xpad_records.py"
            )
            exec_target(target, tail, python=True, schema_python=sub == "regenerate")
        case "errors":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub != "regenerate":
                die(f"Unknown: errors {sub} (expected: regenerate)")
            exec_target(
                "Catalog/generate_error_codes.py", tail, python=True, schema_python=True
            )
        case "diagnose":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "-h", "--help", "help"}:
                exec_target("Diagnostics/backend.sh", ["help"])
            if sub == "record":
                return run_record(tail)
            if sub == "usb-passive":
                return run_usb_passive(tail)
            if sub == "rumble-motors":
                if len(tail) not in {2, 3, 4}:
                    die(
                        "diagnose rumble-motors requires vid pid [intensity] [duration-ms]"
                    )
                exec_target("Diagnostics/rumble-motors.sh", tail)
            if sub in {
                "dext",
                "sdl3",
                "sdl3-gamecontroller",
                "sdl3-hidapi-x360",
                "gamecontroller",
                "backends",
            }:
                if sub == "dext":
                    require("diagnose dext", tail, count=0)
                    exec_target("Diagnostics/dext/diagnose.sh", [])
                exec_target("Diagnostics/backend.sh", [sub, *tail])
            die(
                f"Unknown: diagnose {sub} (expected: record | usb-passive | dext | sdl3 | sdl3-gamecontroller | sdl3-hidapi-x360 | gamecontroller | backends | rumble-motors)"
            )
        case "check":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"profiles", "schemas"}:
                require(f"check {sub}", tail, count=0)
                target = {
                    "profiles": "Catalog/validate_profiles.py",
                    "schemas": "Quality/validate_schemas.py",
                }[sub]
                exec_target(
                    target,
                    [],
                    python=True,
                    schema_python=sub in {"profiles", "schemas"},
                )
            if sub == "driverkit":
                require("check driverkit", tail, count=0)
                exec_target("Build/driverkit.sh", ["validate"])
            if sub == "tools":
                require("check tools", tail, count=0)
                return subprocess.run(
                    [
                        "xmake",
                        "build",
                        "-P",
                        str(PROJECT_DIR / "Tools/SDLGamepadProbe"),
                        "SDLGamepadProbe",
                    ],
                    cwd=PROJECT_DIR,
                    env=env_with(),
                    check=False,
                ).returncode
            die(
                f"Unknown: check {sub} (expected: profiles | schemas | driverkit | tools)"
            )
        case "test":
            if rest != ["parsers-macos14"]:
                die(
                    f"Unknown: test {rest[0] if rest else ''} (expected: parsers-macos14)"
                )
            return subprocess.run(
                ["swift", "run", "ParserCompatibilityHarness"],
                cwd=PROJECT_DIR,
                env=env_with(),
                check=False,
            ).returncode
        case "repair":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub == "stale-dext":
                require("repair stale-dext", tail, count=0)
                exec_target("Diagnostics/dext/repair.py", [], python=True)
            if sub == "swiftpm-module-cache":
                require("repair swiftpm-module-cache", tail, count=0)
                return repair_swiftpm_cache()
            die(f"Unknown: repair {sub} (expected: stale-dext | swiftpm-module-cache)")
        case "launch":
            if not rest or rest[0] != "sdl-gamecontroller":
                die(
                    f"Unknown: launch {rest[0] if rest else ''} (expected: sdl-gamecontroller)"
                )
            exec_target("Diagnostics/sdl/gamecontroller.sh", rest[1:])
        case "hooks":
            if rest not in (["install"], ["validate"]):
                die(
                    f"Unknown: hooks {rest[0] if rest else ''} (expected: install | validate)"
                )
            os.execvpe("lefthook", ["lefthook", rest[0]], env_with())
        case "setup":
            require("setup", rest, count=0)
            return run_commands([["lefthook", "validate"], ["lefthook", "install"]])
        case "package":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "-h", "--help", "help"}:
                package_usage()
                return 0
            if sub != "tester":
                die(f"Unknown: package {sub} (expected: tester)")
            if tail in (["-h"], ["--help"], ["help"]):
                exec_python_with_environment("Release/package_tester.py", [sub, *tail])
            require("package tester", tail, maximum=1)
            exec_python_with_environment("Release/package_tester.py", [sub, *tail])
        case "release":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "help", "-h", "--help"}:
                usage()
                return 0
            if sub == "bump-version":
                require("release bump-version", tail, count=1)
                exec_target("Release/bump_version.py", tail, python=True)
            if sub == "package":
                if tail in (["-h"], ["--help"], ["help"]):
                    exec_python_with_environment("Release/package.py", ["--help"])
                require("release package", tail, maximum=1)
                exec_python_with_environment("Release/package.py", ["release", *tail])
            if sub == "install-local":
                require("release install-local", tail, maximum=1)
                exec_python_with_environment("Release/install_local.py", tail)
            if sub == "notarize":
                action, args = (tail[0], tail[1:]) if tail else ("submit", [])
                limits = {
                    "submit": 0,
                    "history": 0,
                    "status": 1,
                    "log": 1,
                    "store-credentials": 1,
                }
                if action in {"help", "-h", "--help"}:
                    exec_target(
                        "Release/notarize.sh", ["help"], env={"OJD_ENV": "release"}
                    )
                if action not in limits:
                    die(
                        f"Unknown: release notarize {action} (expected: submit | status | history | log | store-credentials)"
                    )
                if len(args) > limits[action]:
                    die(
                        f"release notarize {action} accepts at most one argument"
                        if limits[action]
                        else f"release notarize {action} does not accept arguments"
                    )
                if action == "log" and len(args) != 1:
                    die("release notarize log requires exactly one argument")
                exec_target(
                    "Release/notarize.sh", [action, *args], env={"OJD_ENV": "release"}
                )
            die(
                f"Unknown: release {sub} (expected: bump-version | package | install-local | notarize)"
            )
        case _:
            die(f"Unknown command: {command} (run: ./Scripts/ojd --help)")
    return 0


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    resolver = Resolver(PROJECT_DIR)
    try:
        resolver.resolve(requirements_for(arguments))
    except CapabilityError as error:
        die(error.outcome.detail)
    os.environ.update(resolver.environ)
    return dispatch(arguments)
