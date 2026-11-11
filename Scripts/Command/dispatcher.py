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
  driverkit generate [path]   Generate the DriverKit project into a missing folder
  package tester               Build a private, shareable Developer ID DMG
  release bump-version <version>
                              Update release version references
  release package [version]  Build, notarize, staple, and package a release DMG
  release install-local [version]
                              Package and install the release app locally
  release notarize <command> Run release notarization operations

  docs build-wiki <dir>       Convert wiki/ into GitHub wiki pages in an empty directory
  docs publish-wiki [--dry-run] Publish wiki/ to the GitHub wiki (--dry-run shows the diff only)
  github ensure-auth          Install and authenticate GitHub CLI when needed
  signing install-profiles [--mode all|development|release] [dir]
                               Copy profiles from ~/Documents/Profiles into MobileDevice
  signing configure [--mode all|development|release] [--development-identity <sha1>]
                    [--release-identity <sha1>]
                               Generate .env.dev + .env.release from Keychain + profiles
  signing audit [paths...]     Audit profiles without leaking identifiers
  signing cert-info <cer>      Show safe-ish .cer info (Team ID = Subject OU)
  signing profile-info <pp>    Show safe-ish profile embedded cert info
  signing import-embedded <pp> Import every embedded cert from a profile into Keychain
  signing ci-release-setup     Import GitHub Actions release secrets (CI only)
  signing export-github-secrets
                               Write/import GitHub Actions release secrets

  diagnose dext               Run dext diagnostics (activation, codesign, IORegistry, application service connection)
  diagnose record <json>      Validate a record or probe through the USB DEXT
  diagnose usb-passive <vid> <pid>
                              Print an authorized device's USB descriptor facts (debug build)
  diagnose sdl3 [--seconds N] Run SDL3 probe against the virtual device
  diagnose sdl3-gamecontroller [--seconds N]
                              Run SDL3 through `ojd virtual launch --sdl-gamecontroller-backend` and test rumble
  diagnose sdl3-hidapi-x360 [--seconds N]
                              Run SDL3 through Xbox 360 HIDAPI and test rumble
  diagnose gamecontroller     Run GameController.framework probe
  diagnose browsers [--as <persona>] [--browsers firefox,chrome,safari]
                              Feed every control into each browser's Gamepad API and report its slot
  diagnose backends           Run current backend acceptance loop
  diagnose rumble-motors <vid> <pid> [intensity] [duration-ms]
                              Identify physical rumble actuators interactively
  repair stale-dext           Kill stale DriverKit process copies after upgrade
  catalog regenerate --check Verify the runtime catalog against pinned sources and overrides
  catalog regenerate --write Rebuild the runtime catalog from pinned sources and overrides
  errors regenerate --check   Verify the error code schema enum and wiki table against the catalog
  errors regenerate --write   Rebuild the error code schema enum and wiki table from the catalog
  vocabulary regenerate --check   Verify the wiki control crosswalk table against crosswalk.plist
  vocabulary regenerate --write   Rebuild the wiki control crosswalk table from crosswalk.plist
  check profiles              Check canonical controller records
  check schemas               Validate canonical schemas and a live support report
  check swift                 Build the package and its tests, failing on any warning, then test
  check driverkit             Verify generated DriverKit reproducibility and build
  check tools                 Build the SDL gamepad probe and test the WebRTC bridge package, failing on any warning
  test parsers-macos14        Run focused parser regressions without Swift Testing
  snapshots check             Diff the tree against the equivalence snapshots, per record
  snapshots write             Rewrite the equivalence snapshots from the tree (review the diff)

  shots capture --area <name>|--settings-pane <name>|--all [--ready-timeout <seconds>]
                              Capture the installed app's windows into .ojd-shots/<timestamp>/
                              (areas: Controllers Profiles Library Access Activity; panes: General Notifications Advanced)
                              Waits up to --ready-timeout (default 15) for the app to answer Accessibility

  hooks install|validate      Install or validate repository Git hooks
  setup                       Install required command runner and hooks

Examples:
  ./Scripts/ojd signing install-profiles
  ./Scripts/ojd signing configure
  ./Scripts/ojd diagnose record /tmp/controller.json --validate-only
  ./Scripts/ojd build install-fast dev
  ./Scripts/ojd release bump-version 0.1.0-rc.2

Notes:
  - Most commands expect the app to be installed to /Applications.
  - diagnose sdl3-gamecontroller and diagnose backends fail when it is not installed.
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
    install_hooks,
    run_record,
    run_usb_passive,
    run_without_warnings,
    swift_command,
    swift_test_package,
    validate_hooks,
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
        case "docs":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub == "build-wiki":
                require("docs build-wiki", tail, count=1)
                exec_target("Documentation/wiki/build.py", tail, python=True)
            if sub == "publish-wiki":
                exec_target("Documentation/wiki/publish.py", tail, python=True)
            die(f"Unknown: docs {sub} (expected: build-wiki | publish-wiki)")
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
                "audit",
                "cert-info",
                "profile-info",
                "import-embedded",
                "ci-release-setup",
            }:
                if sub == "ci-release-setup":
                    require(f"signing {sub}", tail, count=0)
                exec_target("Signing/signing.sh", [sub, *tail])
            die(
                f"Unknown: signing {sub} (expected: install-profiles | configure | audit | cert-info | profile-info | import-embedded | ci-release-setup | export-github-secrets)"
            )
        case "catalog":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub != "regenerate":
                die(f"Unknown: catalog {sub} (expected: regenerate)")
            exec_target(
                "Catalog/generate_controller_catalog.py",
                tail,
                python=True,
                schema_python=True,
            )
        case "errors":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub != "regenerate":
                die(f"Unknown: errors {sub} (expected: regenerate)")
            exec_target(
                "Catalog/generate_error_codes.py", tail, python=True, schema_python=True
            )
        case "vocabulary":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub != "regenerate":
                die(f"Unknown: vocabulary {sub} (expected: regenerate)")
            exec_target("Catalog/generate_crosswalk.py", tail, python=True)
        case "diagnose":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"", "-h", "--help", "help"}:
                exec_target("Diagnostics/backend.sh", ["help"])
            if sub == "record":
                return run_record(tail)
            if sub == "usb-passive":
                return run_usb_passive(tail)
            if sub == "browsers":
                exec_target("Diagnostics/browser_gamepad.py", tail, python=True)
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
                f"Unknown: diagnose {sub} (expected: record | usb-passive | dext | browsers | sdl3 | sdl3-gamecontroller | sdl3-hidapi-x360 | gamecontroller | backends | rumble-motors)"
            )
        case "check":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub in {"profiles", "schemas"}:
                require(f"check {sub}", tail, count=0)
                target = {
                    "profiles": "Quality/check_profiles.py",
                    "schemas": "Quality/validate_schemas.py",
                }[sub]
                exec_target(
                    target,
                    [],
                    python=True,
                    schema_python=sub in {"profiles", "schemas"},
                )
            if sub == "swift":
                require("check swift", tail, count=0)
                built, _ = run_without_warnings(
                    swift_command(["build", "--build-tests"]), PROJECT_DIR
                )
                if built:
                    return built
                return subprocess.run(
                    swift_command(["test", "--skip-build", "--no-parallel"]),
                    cwd=PROJECT_DIR,
                    env=env_with(),
                    check=False,
                ).returncode
            if sub == "driverkit":
                require("check driverkit", tail, count=0)
                exec_target("Build/driverkit.sh", ["validate"])
            if sub == "tools":
                require("check tools", tail, count=0)
                # xmake's clang finds no SDK on its own; environment.sh exports SDKROOT.
                probe, _ = run_without_warnings(
                    [
                        "/bin/bash",
                        "-c",
                        'source "$1"; exec xmake build -P "$2" SDLGamepadProbe',
                        "ojd",
                        str(ENVIRONMENT),
                        str(PROJECT_DIR / "Tools/SDLGamepadProbe"),
                    ],
                    PROJECT_DIR,
                )
                # The bridge is its own package, so the root `swift test` never builds it.
                bridge = swift_test_package(PROJECT_DIR / "Tools/WebRTCBridge")
                return probe or bridge
            die(
                f"Unknown: check {sub} (expected: profiles | schemas | swift | driverkit | tools)"
            )
        case "snapshots":
            if rest not in (["check"], ["write"]):
                die(
                    f"Unknown: snapshots {rest[0] if rest else ''} (expected: check | write)"
                )
            exec_target("Quality/equivalence_snapshots.py", rest, python=True)
        case "test":
            if rest != ["parsers-macos14"]:
                die(
                    f"Unknown: test {rest[0] if rest else ''} (expected: parsers-macos14)"
                )
            return subprocess.run(
                swift_command(["run", "ParserCompatibilityHarness"]),
                cwd=PROJECT_DIR,
                env=env_with(),
                check=False,
            ).returncode
        case "repair":
            sub, tail = (rest[0], rest[1:]) if rest else ("", [])
            if sub == "stale-dext":
                require("repair stale-dext", tail, count=0)
                exec_target("Diagnostics/dext/repair.py", [], python=True)
            die(f"Unknown: repair {sub} (expected: stale-dext)")
        case "shots":
            if not rest or rest[0] != "capture":
                found = f" {rest[0]}" if rest else ""
                die(f"Unknown: shots{found} (expected: capture)")
            exec_target("GUI/capture.py", rest[1:], python=True)
        case "hooks":
            if rest not in (["install"], ["validate"]):
                die(
                    f"Unknown: hooks {rest[0] if rest else ''} (expected: install | validate)"
                )
            return install_hooks() if rest[0] == "install" else validate_hooks()
        case "setup":
            require("setup", rest, count=0)
            return install_hooks() or validate_hooks()
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
