"""Capability domain model."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Capability(Enum):
    SCHEMA_PYTHON = "schema Python environment"
    SWIFT_TOOLCHAIN = "Swift toolchain"
    FULL_XCODE = "full Xcode"
    SWIFTLINT = "SwiftLint"
    SHELLCHECK = "ShellCheck"
    JUST = "Just"
    PKG_CONFIG = "pkg-config"
    SDL3 = "SDL3"
    GH = "GitHub CLI"
    GH_AUTH = "GitHub authentication"
    DEVELOPMENT_SIGNING = "development signing"
    RELEASE_SIGNING = "release signing"
    NOTARIZATION = "notarization credentials"
    RUFF = "Ruff"
    XMAKE = "Xmake"


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
        super().__init__(
            outcome.detail or f"{outcome.capability.value}: {outcome.kind.value}"
        )


FORMULAS: dict[Capability, tuple[str, str]] = {
    Capability.SWIFTLINT: ("swiftlint", "swiftlint"),
    Capability.SHELLCHECK: ("shellcheck", "shellcheck"),
    Capability.JUST: ("just", "just"),
    Capability.PKG_CONFIG: ("pkg-config", "pkg-config"),
    Capability.SDL3: ("sdl3", "sdl3"),
    Capability.GH: ("gh", "gh"),
    Capability.RUFF: ("ruff", "ruff"),
    Capability.XMAKE: ("xmake", "xmake"),
}


def _truthy(value: str | None) -> bool:
    return value is not None and value.lower() not in {"", "0", "false", "no"}
