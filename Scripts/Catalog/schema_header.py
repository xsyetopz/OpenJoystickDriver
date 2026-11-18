from __future__ import annotations

from Scripts.Quality import repository_tool

SCHEMA_SUFFIX = ".schema.json"

KINDS = {
    "controller": "Controller",
    "controller-patch": "ControllerPatch",
    "virtual-device": "VirtualDevice",
    "profile": "Profile",
    "mod-package": "ModPackage",
    "error-codes": "ErrorCatalog",
    "crosswalk": "Crosswalk",
    "access-grants": "AccessGrants",
    "protocol-description": "ProtocolDescription",
    "settings": "Settings",
    "service-listener-failure": "ServiceListenerFailure",
    "controller-check": "ControllerCheck",
}


def schema_id(stem: str) -> str:
    return f"{repository_tool.schema_base()}{stem}{SCHEMA_SUFFIX}"


def header(kind: str) -> dict[str, str]:
    return {"apiVersion": repository_tool.api_version(), "kind": kind}
