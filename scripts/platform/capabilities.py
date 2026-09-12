"""Detect and repair prerequisites for repository-owned commands."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Callable, Iterable, Mapping, TextIO


class Capability(Enum):
    SCHEMA_PYTHON = "schema Python environment"
    SWIFT_TOOLCHAIN = "Swift toolchain"
    FULL_XCODE = "full Xcode"
    SWIFTLINT = "SwiftLint"
    LEFTHOOK = "Lefthook"
    JUST = "Just"
    PKG_CONFIG = "pkg-config"
    SDL3 = "SDL3"
    GH = "GitHub CLI"
    GH_AUTH = "GitHub authentication"
    DEVELOPMENT_SIGNING = "development signing"
    RELEASE_SIGNING = "release signing"
    NOTARIZATION = "notarization credentials"


class OutcomeKind(Enum):
    AVAILABLE = "available"
    REPAIRED = "repaired"
    EXTERNALLY_BLOCKED = "externally blocked"
    DECLINED = "declined"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class RepairOutcome:
    capability: Capability
    kind: OutcomeKind
    detail: str = ""


class CapabilityError(RuntimeError):
    def __init__(self, outcome: RepairOutcome):
        self.outcome = outcome
        super().__init__(outcome.detail or f"{outcome.capability.value}: {outcome.kind.value}")


FORMULAS: dict[Capability, tuple[str, str]] = {
    Capability.SWIFTLINT: ("swiftlint", "swiftlint"),
    Capability.LEFTHOOK: ("lefthook", "lefthook"),
    Capability.JUST: ("just", "just"),
    Capability.PKG_CONFIG: ("pkg-config", "pkg-config"),
    Capability.SDL3: ("sdl3", "sdl3"),
    Capability.GH: ("gh", "gh"),
}


def _truthy(value: str | None) -> bool:
    return value is not None and value.lower() not in {"", "0", "false", "no"}


def _load_env_file(path: Path, environ: Mapping[str, str] | None = None) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        if environ is not None:
            home = environ.get("HOME", "")
            value = value.replace("${HOME}", home).replace("$HOME", home)
        values[key.strip()] = os.path.expanduser(value)
    return values


def update_env_value(path: Path, key: str, value: str) -> None:
    """Atomically update one shell environment assignment without touching other keys."""
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


class Resolver:
    def __init__(
        self,
        project_dir: Path,
        *,
        environ: Mapping[str, str] | None = None,
        input_stream: TextIO = sys.stdin,
        output: TextIO = sys.stderr,
        which: Callable[[str, str | None], str | None] | None = None,
        run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        self.project_dir = project_dir
        self.environ = dict(os.environ if environ is None else environ)
        self.input = input_stream
        self.output = output
        self.which = which or (lambda executable, path: shutil.which(executable, path=path))
        self.run = run

    @property
    def interactive(self) -> bool:
        return (
            not _truthy(self.environ.get("CI"))
            and not _truthy(self.environ.get("OJD_NONINTERACTIVE"))
            and self.input.isatty()
        )

    def resolve(self, capabilities: Iterable[Capability]) -> list[RepairOutcome]:
        outcomes: list[RepairOutcome] = []
        for capability in dict.fromkeys(capabilities):
            outcome = self.ensure(capability)
            outcomes.append(outcome)
            if outcome.kind not in {OutcomeKind.AVAILABLE, OutcomeKind.REPAIRED}:
                raise CapabilityError(outcome)
        return outcomes

    def ensure(self, capability: Capability) -> RepairOutcome:
        if capability in FORMULAS:
            return self._ensure_formula(capability)
        if capability == Capability.SCHEMA_PYTHON:
            return self._ensure_schema_python()
        if capability == Capability.SWIFT_TOOLCHAIN:
            return self._ensure_swift_toolchain()
        if capability == Capability.FULL_XCODE:
            return self._ensure_full_xcode()
        if capability == Capability.GH_AUTH:
            return self._ensure_gh_auth()
        if capability in {Capability.DEVELOPMENT_SIGNING, Capability.RELEASE_SIGNING}:
            return self._ensure_signing(capability)
        if capability == Capability.NOTARIZATION:
            return self._ensure_notarization()
        return RepairOutcome(capability, OutcomeKind.UNSUPPORTED, "unknown capability")

    def _command_path(self, executable: str) -> str | None:
        return self.which(executable, self.environ.get("PATH"))

    def _run(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        return self.run(command, env=self.environ, text=True, check=False, **kwargs)

    def _ensure_formula(self, capability: Capability) -> RepairOutcome:
        formula, executable = FORMULAS[capability]
        if self._formula_available(capability, executable):
            return RepairOutcome(capability, OutcomeKind.AVAILABLE)
        brew = self._command_path("brew")
        resume = "Re-run the original command after installation."
        if not brew:
            detail = f"Homebrew is required to install {formula}. {resume}"
            if self.interactive:
                self._run(["open", "https://brew.sh/"])
                detail = f"Opened the official Homebrew installation page. {detail}"
            return RepairOutcome(capability, OutcomeKind.EXTERNALLY_BLOCKED, detail)
        if not self.interactive:
            return RepairOutcome(
                capability,
                OutcomeKind.UNSUPPORTED,
                f"{formula} is missing; noninteractive mode will not install host software.",
            )
        print(f"Install Homebrew formula {formula}? [y/N] ", end="", file=self.output, flush=True)
        if self.input.readline().strip().lower() not in {"y", "yes"}:
            return RepairOutcome(capability, OutcomeKind.DECLINED, f"Installation declined: {formula}")
        result = self._run([brew, "install", formula])
        if result.returncode or not self._formula_available(capability, executable):
            return RepairOutcome(
                capability,
                OutcomeKind.UNSUPPORTED,
                f"Homebrew could not install {formula}; check the network and retry.",
            )
        return RepairOutcome(capability, OutcomeKind.REPAIRED)

    def _formula_available(self, capability: Capability, executable: str) -> bool:
        if capability != Capability.SDL3:
            return self._command_path(executable) is not None
        pkg_config = self._command_path("pkg-config")
        if not pkg_config:
            return False
        result = self._run(
            [pkg_config, "--exists", "sdl3"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0

    def _ensure_schema_python(self) -> RepairOutcome:
        destination = self.project_dir / ".build/schema-validator"
        python = destination / "bin/python"
        if python.is_file() and self._python_has_jsonschema(python):
            return RepairOutcome(Capability.SCHEMA_PYTHON, OutcomeKind.AVAILABLE)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix="schema-validator.", dir=destination.parent))
        try:
            result = self._run([sys.executable, "-m", "venv", str(temporary)])
            if result.returncode:
                raise OSError("python venv creation failed")
            result = self._run(
                [
                    str(temporary / "bin/python"),
                    "-m",
                    "pip",
                    "install",
                    "-r",
                    str(self.project_dir / "scripts/quality/requirements.txt"),
                ]
            )
            if result.returncode or not self._python_has_jsonschema(temporary / "bin/python"):
                raise OSError("dependency installation failed")
            if destination.exists():
                shutil.rmtree(destination)
            os.replace(temporary, destination)
        except OSError:
            shutil.rmtree(temporary, ignore_errors=True)
            return RepairOutcome(
                Capability.SCHEMA_PYTHON,
                OutcomeKind.UNSUPPORTED,
                "Could not create the schema validator environment; check Python and network access.",
            )
        return RepairOutcome(Capability.SCHEMA_PYTHON, OutcomeKind.REPAIRED)

    def _python_has_jsonschema(self, python: Path) -> bool:
        result = self._run(
            [str(python), "-c", "import jsonschema"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0

    def _ensure_swift_toolchain(self) -> RepairOutcome:
        if self._command_path("swift") and self._command_path("xcrun"):
            return RepairOutcome(Capability.SWIFT_TOOLCHAIN, OutcomeKind.AVAILABLE)
        return self._guide_xcode(Capability.SWIFT_TOOLCHAIN)

    def _ensure_full_xcode(self) -> RepairOutcome:
        developer_dir = self.environ.get("DEVELOPER_DIR", "")
        candidates = [Path(developer_dir)] if developer_dir else []
        applications = Path(self.environ.get("OJD_APPLICATIONS_DIR", "/Applications"))
        candidates.extend(
            path / "Contents/Developer"
            for path in sorted(applications.glob("Xcode*.app"), reverse=True)
        )
        for candidate in candidates:
            if (candidate / "usr/bin/xcodebuild").is_file():
                self.environ["DEVELOPER_DIR"] = str(candidate)
                return RepairOutcome(Capability.FULL_XCODE, OutcomeKind.AVAILABLE)
        return self._guide_xcode(Capability.FULL_XCODE)

    def _guide_xcode(self, capability: Capability) -> RepairOutcome:
        detail = "Install full Xcode from the Mac App Store, launch it once, then re-run the original command."
        if self.interactive:
            self._run(["open", "macappstore://itunes.apple.com/app/id497799835"])
            detail = f"Opened Xcode in the Mac App Store. {detail}"
        return RepairOutcome(capability, OutcomeKind.EXTERNALLY_BLOCKED, detail)

    def _ensure_gh_auth(self) -> RepairOutcome:
        gh = self._command_path("gh")
        if not gh:
            return RepairOutcome(Capability.GH_AUTH, OutcomeKind.UNSUPPORTED, "GitHub CLI is missing")
        status = self._run([gh, "auth", "status"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if status.returncode == 0:
            return RepairOutcome(Capability.GH_AUTH, OutcomeKind.AVAILABLE)
        if not self.interactive:
            return RepairOutcome(
                Capability.GH_AUTH,
                OutcomeKind.UNSUPPORTED,
                "GitHub CLI is not authenticated; noninteractive mode cannot authenticate.",
            )
        result = self._run([gh, "auth", "login"])
        kind = OutcomeKind.REPAIRED if result.returncode == 0 else OutcomeKind.DECLINED
        return RepairOutcome(Capability.GH_AUTH, kind, "GitHub authentication did not complete.")

    def _ensure_signing(self, capability: Capability) -> RepairOutcome:
        mode = "release" if capability == Capability.RELEASE_SIGNING else "dev"
        env_file = self.project_dir / f".env.{mode}"
        values = _load_env_file(env_file, self.environ)
        required = {
            "CODESIGN_IDENTITY",
            "DEVELOPMENT_TEAM",
            "DEXT_BUILD_IDENTITY",
            "DEXT_BUILD_PROFILE",
            "DEXT_PROVISIONING_PROFILE",
            "GUI_PROVISIONING_PROFILE",
        }
        paths_available = required <= values.keys() and all(
            values[key] and Path(values[key]).exists()
            for key in {"DEXT_PROVISIONING_PROFILE", "GUI_PROVISIONING_PROFILE"}
        )
        identities_available = False
        if paths_available:
            result = self._run(
                ["security", "find-identity", "-v", "-p", "codesigning"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            identities_available = result.returncode == 0 and all(
                values[key].lower() in result.stdout.lower()
                for key in {"CODESIGN_IDENTITY", "DEXT_BUILD_IDENTITY"}
            )
        if paths_available and identities_available:
            return RepairOutcome(capability, OutcomeKind.AVAILABLE)
        if not self.interactive:
            return RepairOutcome(
                capability,
                OutcomeKind.UNSUPPORTED,
                f"{mode} signing is not configured; noninteractive mode cannot acquire Apple assets.",
            )
        signing = self.project_dir / "scripts/signing/signing.sh"
        signing_mode = "release" if mode == "release" else "development"
        env = self.environ | {"OJD_SIGNING_MODE": signing_mode}
        result = self.run(["/usr/bin/env", "bash", str(signing), "configure"], env=env, text=True, check=False)
        if result.returncode == 0:
            return RepairOutcome(capability, OutcomeKind.REPAIRED)
        result = self.run(["/usr/bin/env", "bash", str(signing), "install-profiles"], env=env, text=True, check=False)
        if result.returncode:
            return RepairOutcome(
                capability,
                OutcomeKind.EXTERNALLY_BLOCKED,
                f"Required Apple provisioning profiles were not found. Re-run the original command after downloading them from the Apple Developer portal.",
            )
        result = self.run(["/usr/bin/env", "bash", str(signing), "configure"], env=env, text=True, check=False)
        if result.returncode:
            return RepairOutcome(capability, OutcomeKind.EXTERNALLY_BLOCKED, "Signing assets are incomplete or do not match.")
        return RepairOutcome(capability, OutcomeKind.REPAIRED)

    def _ensure_notarization(self) -> RepairOutcome:
        env_file = self.project_dir / ".env.release"
        values = _load_env_file(env_file, self.environ)
        if _truthy(self.environ.get("CI")) and all(
            self.environ.get(key) or values.get(key)
            for key in ("NOTARIZE_APPLE_ID", "NOTARIZE_PASSWORD", "DEVELOPMENT_TEAM")
        ):
            return RepairOutcome(Capability.NOTARIZATION, OutcomeKind.AVAILABLE)
        existing_profile = values.get("NOTARIZE_KEYCHAIN_PROFILE", "")
        if existing_profile:
            result = self._run(
                [
                    "xcrun",
                    "notarytool",
                    "history",
                    "--keychain-profile",
                    existing_profile,
                    "--output-format",
                    "json",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                return RepairOutcome(Capability.NOTARIZATION, OutcomeKind.AVAILABLE)
            return RepairOutcome(
                Capability.NOTARIZATION,
                OutcomeKind.UNSUPPORTED,
                f"Notarization Keychain profile {existing_profile!r} could not be validated; unlock Keychain or store credentials again.",
            )
        if not self.interactive:
            return RepairOutcome(
                Capability.NOTARIZATION,
                OutcomeKind.UNSUPPORTED,
                "Notarization Keychain credentials are missing; noninteractive mode cannot prompt for them.",
            )
        apple_id = values.get("NOTARIZE_APPLE_ID", "")
        if not apple_id:
            print("Apple ID for notarization: ", end="", file=self.output, flush=True)
            apple_id = self.input.readline().strip()
        if not apple_id:
            return RepairOutcome(Capability.NOTARIZATION, OutcomeKind.DECLINED, "Apple ID was not provided.")
        team = values.get("DEVELOPMENT_TEAM", "")
        if not team:
            return RepairOutcome(Capability.NOTARIZATION, OutcomeKind.UNSUPPORTED, "Release signing team is missing.")
        profile = self.environ.get("OJD_NOTARIZE_PROFILE", "OpenJoystickDriver")
        result = self._run(
            ["xcrun", "notarytool", "store-credentials", profile, "--apple-id", apple_id, "--team-id", team]
        )
        if result.returncode:
            return RepairOutcome(
                Capability.NOTARIZATION,
                OutcomeKind.UNSUPPORTED,
                "notarytool did not validate credentials; .env.release was left unchanged.",
            )
        update_env_value(env_file, "NOTARIZE_APPLE_ID", apple_id)
        update_env_value(env_file, "NOTARIZE_KEYCHAIN_PROFILE", profile)
        return RepairOutcome(Capability.NOTARIZATION, OutcomeKind.REPAIRED)


def requirements_for(argv: list[str]) -> tuple[Capability, ...]:
    route = tuple(argv)
    if any(argument in {"-h", "--help", "help"} for argument in route[1:]):
        return ()
    if route[:2] == ("catalog", "regenerate") and len(route) >= 3:
        return (Capability.SCHEMA_PYTHON,)
    if route == ("check", "profiles"):
        return (Capability.SCHEMA_PYTHON,)
    if route == ("check", "schemas"):
        return (Capability.SCHEMA_PYTHON, Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route == ("lint",):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.SWIFTLINT)
    if route == ("format",):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route == ("check", "fast"):
        return (Capability.SCHEMA_PYTHON, Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.SWIFTLINT)
    if route in {("check", "all"), ("check", "driverkit")}:
        return (Capability.SCHEMA_PYTHON, Capability.SWIFT_TOOLCHAIN, Capability.SWIFTLINT, Capability.FULL_XCODE)
    if route[:2] == ("test", "swift"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route[:2] == ("driverkit", "generate") and len(route) <= 3:
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route == ("build", "dev") or route in {("build", "install", "dev"), ("build", "install-fast", "dev")}:
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.DEVELOPMENT_SIGNING)
    if route == ("build", "dext"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.DEVELOPMENT_SIGNING)
    if route == ("build", "release") or route == ("build", "install", "release"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.RELEASE_SIGNING)
    if route == ("package", "tester") or (
        route[:2] in {("release", "package"), ("release", "install-local")} and len(route) <= 3
    ):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.RELEASE_SIGNING, Capability.NOTARIZATION)
    if route[:2] == ("release", "notarize") and (len(route) < 3 or route[2] != "store-credentials"):
        return (Capability.FULL_XCODE, Capability.RELEASE_SIGNING, Capability.NOTARIZATION)
    if route[:3] == ("release", "notarize", "store-credentials"):
        return (Capability.FULL_XCODE, Capability.RELEASE_SIGNING)
    if route[:2] == ("docs", "export-external-issues"):
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] == ("github", "ensure-auth"):
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] == ("signing", "export-github-secrets") and "--apply" in route:
        return (Capability.GH, Capability.GH_AUTH)
    if route[:2] in {("diagnose", "sdl3"), ("diagnose", "sdl3-gamecontroller"), ("diagnose", "sdl3-hidapi-x360"), ("diagnose", "backends")}:
        base = (Capability.FULL_XCODE, Capability.PKG_CONFIG, Capability.SDL3)
        return (Capability.SWIFT_TOOLCHAIN, *base) if route[:2] == ("diagnose", "backends") else base
    if route[:2] in {("diagnose", "record"), ("diagnose", "gamecontroller")}:
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route[:2] == ("diagnose", "rumble-motors"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE, Capability.DEVELOPMENT_SIGNING)
    if route == ("test", "parsers-macos14"):
        return (Capability.SWIFT_TOOLCHAIN, Capability.FULL_XCODE)
    if route[:2] == ("hooks", "install") or route[:2] == ("hooks", "validate"):
        return (Capability.LEFTHOOK,)
    if route == ("setup",):
        return (Capability.JUST, Capability.LEFTHOOK)
    return ()
