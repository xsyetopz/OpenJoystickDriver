#!/usr/bin/env python3
"""Validate canonical OpenJoystickDriver controller records."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
RECORD_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller.schema.json"
)

PROTOCOLS = {
    "GIP": {
        "variants": {"xboxOriginal", "xboxOne", "unknown"},
        "flags": {
            "dpadToButtons", "triggersToButtons", "sticksToNull", "shareButton",
            "paddles", "profileButton", "shareOffset",
        },
    },
    "Xbox360": {
        "variants": {"xbox360", "xbox360Wireless", "unknown"},
        "flags": {"dpadToButtons", "triggersToButtons", "sticksToNull"},
    },
    "DS3": {
        "variants": {"dualShock3", "unknown"},
        "flags": {
            "gyro", "accelerometer", "battery", "experimental",
            "needsHardwareTest",
        },
    },
    "DS4": {
        "variants": {"dualShock4", "unknown"},
        "flags": {
            "touchpad", "gyro", "accelerometer", "battery", "lightbar",
        },
    },
    "DualSense": {
        "variants": {"dualSense", "unknown"},
        "flags": {
            "touchpad", "gyro", "accelerometer", "battery", "lightbar",
            "microphoneMute", "adaptiveTriggers", "experimental",
            "needsHardwareTest",
        },
    },
    "SteamController": {
        "variants": {"steamController", "unknown"},
        "flags": {
            "lizardMode", "trackpads", "gyro", "battery", "wirelessReceiver",
            "experimental", "needsHardwareTest",
        },
    },
    "SwitchPro": {
        "variants": {"switchPro", "unknown"},
        "flags": {
            "usbHandshake", "calibration", "imu", "rumble", "experimental",
            "needsHardwareTest",
        },
    },
    "XboxAdaptiveJoystick": {
        "variants": {"xboxAdaptiveJoystick", "unknown"},
        "flags": {
            "rawUSBPackets", "genericHIDPackets", "experimental",
            "needsHardwareTest",
        },
    },
    "GenericHID": {"variants": {"genericHID"}, "flags": set()},
}
SOURCES = {
    "local-hardware", "linux-xpad.c", "linux-hid-steam.c",
    "linux-hid-playstation.c", "linux-hid-sony.c", "linux-hid-nintendo.c",
    "tester-packets",
}
STARTUP_PACKETS = {
    "powerOn", "xboxOneSInit", "extraInput", "horiAck", "ledOn",
    "authDone", "rumbleBegin", "rumbleEnd",
}
ROOT_KEYS = {
    "$schema", "vendor_id", "product_id", "transport", "protocol", "usb",
    "provenance",
}


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def require_object(value: Any, path: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{path} must be an object")
    return value


def require_keys(
    value: dict[str, Any],
    allowed: set[str],
    required: set[str],
    path: str,
) -> None:
    unknown = sorted(set(value) - allowed)
    missing = sorted(required - set(value))
    require(not unknown, f"{path} has unknown fields: {', '.join(unknown)}")
    require(not missing, f"{path} is missing fields: {', '.join(missing)}")


def require_int(value: Any, path: str, minimum: int, maximum: int) -> int:
    require(
        isinstance(value, int) and not isinstance(value, bool),
        f"{path} must be an integer",
    )
    require(minimum <= value <= maximum, f"{path} must be in {minimum}...{maximum}")
    return value


def require_string(value: Any, path: str) -> str:
    require(isinstance(value, str) and value, f"{path} must be a non-empty string")
    return value


def expected_relative_path(vendor_id: int, product_id: int) -> pathlib.Path:
    return pathlib.Path(f"{vendor_id:04x}") / f"{vendor_id:04x}-{product_id:04x}.json"


def validate_record(
    path: pathlib.Path,
    *,
    enforce_path: bool = True,
) -> tuple[int, int, str, bool]:
    try:
        root = require_object(json.loads(path.read_text()), "$")
    except json.JSONDecodeError as error:
        raise ValidationError(f"invalid JSON: {error}") from error

    require_keys(
        root,
        ROOT_KEYS,
        {"$schema", "vendor_id", "product_id", "transport", "protocol", "provenance"},
        "$",
    )
    require(root["$schema"] == SCHEMA_ID, "$schema must reference controller.schema.json")
    vendor_id = require_int(root["vendor_id"], "vendor_id", 1, 65535)
    product_id = require_int(root["product_id"], "product_id", 0, 65535)

    if enforce_path:
        relative = path.relative_to(RECORD_DIR)
        require(
            relative == expected_relative_path(vendor_id, product_id),
            f"path must be {expected_relative_path(vendor_id, product_id)}",
        )

    transport = require_string(root["transport"], "transport")
    require(transport in {"usb", "hid"}, "transport must be usb or hid")

    protocol = require_object(root["protocol"], "protocol")
    require_keys(
        protocol,
        {"driver", "variant", "flags", "startup_packets"},
        {"driver", "variant"},
        "protocol",
    )
    driver = require_string(protocol["driver"], "protocol.driver")
    require(driver in PROTOCOLS, f"unsupported protocol.driver: {driver}")
    variant = require_string(protocol["variant"], "protocol.variant")
    require(
        variant in PROTOCOLS[driver]["variants"],
        f"protocol.variant {variant} is invalid for {driver}",
    )
    flags = protocol.get("flags", [])
    require(isinstance(flags, list), "protocol.flags must be an array")
    require(all(isinstance(flag, str) and flag for flag in flags), "protocol.flags must contain strings")
    require(len(flags) == len(set(flags)), "protocol.flags must not contain duplicates")
    invalid_flags = sorted(set(flags) - PROTOCOLS[driver]["flags"])
    require(not invalid_flags, f"unsupported protocol.flags: {', '.join(invalid_flags)}")

    startup = protocol.get("startup_packets", [])
    require(isinstance(startup, list), "protocol.startup_packets must be an array")
    if "startup_packets" in protocol:
        require(startup, "protocol.startup_packets must not be empty when present")
    require(len(startup) == len(set(startup)), "protocol.startup_packets must not contain duplicates")
    invalid_packets = sorted(set(startup) - STARTUP_PACKETS)
    require(not invalid_packets, f"unsupported startup packets: {', '.join(invalid_packets)}")
    require(not startup or driver == "GIP", "startup packets require GIP")
    require(
        startup != ["powerOn", "ledOn", "authDone"],
        "default GIP startup packets must be omitted",
    )

    usb = root.get("usb")
    if usb is not None:
        require(transport == "usb", "usb overrides require usb transport")
        usb = require_object(usb, "usb")
        require_keys(
            usb,
            {"interface", "configuration", "post_handshake_settle_ms", "endpoints"},
            set(),
            "usb",
        )
        require(usb, "usb override must not be empty")
        if "interface" in usb:
            interface = require_int(usb["interface"], "usb.interface", 0, 255)
            require(interface != 0, "default USB interface must be omitted")
        if "configuration" in usb:
            require(
                usb["configuration"] == "set1-before-claim",
                "unsupported usb.configuration",
            )
        if "post_handshake_settle_ms" in usb:
            require_int(
                usb["post_handshake_settle_ms"],
                "usb.post_handshake_settle_ms",
                1,
                60000,
            )
        if "endpoints" in usb:
            endpoints = require_object(usb["endpoints"], "usb.endpoints")
            require_keys(endpoints, {"in", "out"}, {"in", "out"}, "usb.endpoints")
            input_endpoint = require_int(endpoints["in"], "usb.endpoints.in", 128, 255)
            output_endpoint = require_int(endpoints["out"], "usb.endpoints.out", 1, 127)
            defaults = (129, 1) if driver == "Xbox360" else (130, 2)
            require(
                (input_endpoint, output_endpoint) != defaults,
                "default protocol endpoints must be omitted",
            )

    provenance = require_object(root["provenance"], "provenance")
    require_keys(
        provenance,
        {"source", "revision", "verified"},
        {"source", "verified"},
        "provenance",
    )
    source = require_string(provenance["source"], "provenance.source")
    require(source in SOURCES, f"unsupported provenance.source: {source}")
    require(
        isinstance(provenance["verified"], bool),
        "provenance.verified must be a boolean",
    )
    if "revision" in provenance:
        require_string(provenance["revision"], "provenance.revision")

    return vendor_id, product_id, driver, provenance["verified"]


def validate_catalog(record_dir: pathlib.Path = RECORD_DIR) -> list[pathlib.Path]:
    records = sorted(record_dir.glob("*/*.json"))
    require(records, f"no controller records found in {record_dir}")
    seen: dict[tuple[int, int], pathlib.Path] = {}
    for path in records:
        vendor_id, product_id, _, _ = validate_record(
            path,
            enforce_path=record_dir == RECORD_DIR,
        )
        key = (vendor_id, product_id)
        require(key not in seen, f"{path}: duplicate identity also in {seen.get(key)}")
        seen[key] = path
    return records


def main() -> int:
    try:
        records = validate_catalog()
    except Exception as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1

    for path in records:
        print(f"[OK] {path.relative_to(ROOT)}")
    print(f"Validated {len(records)} canonical controller record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
