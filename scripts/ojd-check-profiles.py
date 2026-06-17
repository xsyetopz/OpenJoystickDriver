#!/usr/bin/env python3
"""Check bundled controller profiles without third-party dependencies."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any, Callable, TypeVar

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
DEVICE_SCHEMA_DIR = ROOT / "Resources" / "Schemas" / "Devices"
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller-profile.schema.json"
)
DEVICE_SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/device-profile.schema.json"
)

PROTOCOLS = {
    "GIP": {
        "variants": {"xboxOriginal", "xbox360", "xbox360Wireless", "xboxOne", "unknown"},
        "mapping_flags": {
            "dpadToButtons",
            "triggersToButtons",
            "sticksToNull",
            "shareButton",
            "paddles",
            "profileButton",
            "shareOffset",
        },
    },
    "Xbox360": {
        "variants": {"xbox360", "unknown"},
        "mapping_flags": {"dpadToButtons", "triggersToButtons", "sticksToNull"},
    },
    "DS3": {
        "variants": {"dualShock3", "unknown"},
        "mapping_flags": {"gyro", "accelerometer", "battery", "experimental", "needsHardwareTest"},
    },
    "DS4": {
        "variants": {"dualShock4", "unknown"},
        "mapping_flags": {"touchpad", "gyro", "accelerometer", "battery", "lightbar"},
    },
    "DualSense": {
        "variants": {"dualSense", "unknown"},
        "mapping_flags": {
            "touchpad",
            "gyro",
            "accelerometer",
            "battery",
            "lightbar",
            "microphoneMute",
            "adaptiveTriggers",
            "experimental",
            "needsHardwareTest",
        },
    },
    "SteamController": {
        "variants": {"steamController", "unknown"},
        "mapping_flags": {
            "lizardMode",
            "trackpads",
            "gyro",
            "battery",
            "wirelessReceiver",
            "experimental",
            "needsHardwareTest",
        },
    },
    "SwitchPro": {
        "variants": {"switchPro", "unknown"},
        "mapping_flags": {"usbHandshake", "calibration", "imu", "rumble", "experimental", "needsHardwareTest"},
    },
    "XboxAdaptiveJoystick": {
        "variants": {"xboxAdaptiveJoystick", "unknown"},
        "mapping_flags": {"rawUSBPackets", "genericHIDPackets", "experimental", "needsHardwareTest"},
    },
    "GenericHID": {
        "variants": {"genericHID"},
        "mapping_flags": set(),
    },
}

BACKENDS = {"driverKitHID", "userSpaceHID", "gameControllerVirtual"}
VIRTUAL_PROFILES = {"xboxOneS"}
PROFILE_SOURCES = {
    "local-hardware",
    "linux-xpad.c",
    "linux-hid-steam.c",
    "linux-hid-playstation.c",
    "linux-hid-sony.c",
    "linux-hid-nintendo.c",
    "tester-packets",
}
GIP_STARTUP_PACKETS = {
    "powerOn",
    "xboxOneSInit",
    "extraInput",
    "horiAck",
    "ledOn",
    "authDone",
    "rumbleBegin",
    "rumbleEnd",
}
T = TypeVar("T")


class ProfileCheckError(Exception):
    pass


class CheckState:
    def __init__(self):
        self.seen_profiles: dict[tuple[int, int], pathlib.Path] = {}
        self.profile_protocols: dict[tuple[int, int], tuple[str, bool]] = {}
        self.device_schemas: dict[tuple[int, int], pathlib.Path] = {}
        self.failures = 0

    def fail(self, path: pathlib.Path, error: Exception) -> None:
        self.failures += 1
        print(f"[FAIL] {path.relative_to(ROOT)}: {error}", file=sys.stderr)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProfileCheckError(message)


def require_object(value: Any, path: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{path} must be an object")
    return value


def require_string(value: Any, path: str) -> str:
    require(isinstance(value, str) and value, f"{path} must be a non-empty string")
    return value


def require_bool(value: Any, path: str) -> bool:
    require(isinstance(value, bool), f"{path} must be a boolean")
    return value


def require_int(value: Any, path: str, minimum: int, maximum: int | None = None) -> int:
    require(isinstance(value, int) and not isinstance(value, bool), f"{path} must be an integer")
    require(value >= minimum, f"{path} must be >= {minimum}")
    if maximum is not None:
        require(value <= maximum, f"{path} must be <= {maximum}")
    return value


def require_string_list(value: Any, path: str) -> list[str]:
    require(isinstance(value, list), f"{path} must be an array")
    result = [require_string(item, f"{path}[{idx}]") for idx, item in enumerate(value)]
    require(len(result) == len(set(result)), f"{path} must not contain duplicates")
    return result


def require_member(value: str, allowed: set[str], path: str, description: str) -> None:
    require(value in allowed, f"{path} is unsupported: {description}")


def require_subset(values: list[str], allowed: set[str], path: str, description: str) -> None:
    invalid = sorted(set(values) - allowed)
    require(not invalid, f"{path} invalid for {description}: {', '.join(invalid)}")


def load_json_object(path: pathlib.Path) -> dict[str, Any]:
    return require_object(json.loads(path.read_text()), "$")


def check_schema_reference(root: dict[str, Any], expected: set[str] | str, name: str) -> None:
    allowed = {expected} if isinstance(expected, str) else expected
    require(root.get("$schema") in allowed, f"$schema must reference {name}")


def check_usb_common(usb: dict[str, Any], prefix: str) -> None:
    require_int(usb.get("interface"), f"{prefix}.interface", 0)
    usb_class = require_int(usb.get("class"), f"{prefix}.class", 0, 255)
    require(usb_class in {3, 255}, f"{prefix}.class must be 3 or 255")
    configuration = usb.get("configuration")
    if configuration is not None:
        require(configuration == "set1BeforeClaim", f"{prefix}.configuration is unknown")
    require_int(usb.get("post_handshake_settle_ms", 0), f"{prefix}.post_handshake_settle_ms", 0)


def check_controller_endpoints(usb: dict[str, Any], transport: str) -> None:
    endpoints = usb.get("endpoints")
    if endpoints is None:
        require(transport != "usb", "input.usb.endpoints is required for usb transport")
        return
    endpoint_obj = require_object(endpoints, "input.usb.endpoints")
    require_int(endpoint_obj.get("in"), "input.usb.endpoints.in", 0, 255)
    require_int(endpoint_obj.get("out"), "input.usb.endpoints.out", 0, 255)


def check_device_endpoints(usb: dict[str, Any]) -> None:
    endpoints = require_object(usb.get("endpoints"), "usb.endpoints")
    for direction in ("in", "out"):
        endpoint = require_object(endpoints.get(direction), f"usb.endpoints.{direction}")
        require_int(endpoint.get("address"), f"usb.endpoints.{direction}.address", 0, 255)
        endpoint_type = require_string(endpoint.get("type"), f"usb.endpoints.{direction}.type")
        require(endpoint_type in {"interrupt", "bulk"}, f"usb.endpoints.{direction}.type is unsupported")
        require_int(endpoint.get("max_packet"), f"usb.endpoints.{direction}.max_packet", 1)


def check_identity(root: dict[str, Any]) -> tuple[int, int]:
    identity = require_object(root.get("identity"), "identity")
    vid = require_int(identity.get("vendor_id"), "identity.vendor_id", 1, 65535)
    pid = require_int(identity.get("product_id"), "identity.product_id", 0, 65535)
    require_string(identity.get("name"), "identity.name")
    require_string(identity.get("short_name"), "identity.short_name")
    return vid, pid


def check_input(root: dict[str, Any]) -> None:
    input_section = require_object(root.get("input"), "input")
    transport = require_string(input_section.get("transport"), "input.transport")
    require(transport in {"usb", "hid"}, "input.transport must be usb or hid")
    usb = require_object(input_section.get("usb"), "input.usb")
    check_usb_common(usb, "input.usb")
    check_controller_endpoints(usb, transport)


def check_protocol(root: dict[str, Any]) -> str:
    protocol = require_object(root.get("protocol"), "protocol")
    driver = require_string(protocol.get("driver"), "protocol.driver")
    require(driver in PROTOCOLS, f"protocol.driver is unsupported: {driver}")
    variant = require_string(protocol.get("variant"), "protocol.variant")
    require(variant in PROTOCOLS[driver]["variants"], f"protocol.variant {variant} is invalid for {driver}")
    flags = require_string_list(protocol.get("mapping_flags", []), "protocol.mapping_flags")
    require_subset(flags, PROTOCOLS[driver]["mapping_flags"], "protocol.mapping_flags", driver)
    check_startup_packets(protocol, driver)
    return driver


def check_startup_packets(protocol: dict[str, Any], driver: str) -> None:
    packets = require_string_list(protocol.get("startup_packets", []), "protocol.startup_packets")
    if not packets:
        return
    require(driver == "GIP", "protocol.startup_packets is only valid for GIP")
    invalid = sorted(set(packets) - GIP_STARTUP_PACKETS)
    require(not invalid, f"protocol.startup_packets invalid: {', '.join(invalid)}")


def check_output(root: dict[str, Any]) -> None:
    output = require_object(root.get("output"), "output")
    virtual_profile = require_string(output.get("virtual_profile"), "output.virtual_profile")
    require_member(virtual_profile, VIRTUAL_PROFILES, "output.virtual_profile", virtual_profile)
    backends = require_string_list(output.get("preferred_backends"), "output.preferred_backends")
    require(backends, "output.preferred_backends must not be empty")
    require_subset(backends, BACKENDS, "output.preferred_backends", "output")


def check_provenance(root: dict[str, Any]) -> bool:
    provenance = root.get("provenance")
    if provenance is None:
        return True
    provenance_obj = require_object(provenance, "provenance")
    source = require_string(provenance_obj.get("source"), "provenance.source")
    require_member(source, PROFILE_SOURCES, "provenance.source", source)
    return require_bool(provenance_obj.get("hardware_verified"), "provenance.hardware_verified")


def check_profile(path: pathlib.Path) -> tuple[int, int, str, bool]:
    root = load_json_object(path)
    check_schema_reference(
        root,
        {"../../../../../Resources/Schemas/controller-profile.schema.json", SCHEMA_ID},
        "controller-profile.schema.json",
    )
    require_string(root.get("profile_version"), "profile_version")
    vid, pid = check_identity(root)
    check_input(root)
    driver = check_protocol(root)
    check_output(root)
    hardware_verified = check_provenance(root)
    return vid, pid, driver, hardware_verified


def check_device_schema(path: pathlib.Path) -> tuple[int, int]:
    root = load_json_object(path)
    check_schema_reference(root, DEVICE_SCHEMA_ID, "device-profile.schema.json")
    vid = require_int(root.get("vendor_id"), "vendor_id", 1, 65535)
    pid = require_int(root.get("product_id"), "product_id", 0, 65535)
    require_string(root.get("name"), "name")
    protocol = require_string(root.get("protocol"), "protocol")
    require(protocol in PROTOCOLS, f"protocol is unsupported: {protocol}")
    usb = require_object(root.get("usb"), "usb")
    check_usb_common(usb, "usb")
    check_device_endpoints(usb)
    init_sequence = root.get("init_sequence")
    require(isinstance(init_sequence, list) and init_sequence, "init_sequence must be a non-empty array")
    input_commands = require_object(root.get("input_commands"), "input_commands")
    require("input" in input_commands, "input_commands.input is required")
    return vid, pid


def checked(path: pathlib.Path, checker: Callable[[pathlib.Path], T], state: CheckState) -> T | None:
    try:
        value = checker(path)
        print(f"[OK] {path.relative_to(ROOT)}")
        return value
    except Exception as error:
        state.fail(path, error)
        return None


def check_profiles(paths: list[pathlib.Path], state: CheckState) -> None:
    for profile in paths:
        result = checked(profile, check_profile, state)
        if result is None:
            continue
        vid, pid, driver, hardware_verified = result
        key = (vid, pid)
        if key in state.seen_profiles:
            state.fail(profile, ProfileCheckError(f"duplicate VID/PID also in {state.seen_profiles[key].name}"))
            continue
        state.seen_profiles[key] = profile
        state.profile_protocols[key] = (driver, hardware_verified)


def check_device_schemas(paths: list[pathlib.Path], state: CheckState) -> None:
    for schema in paths:
        key = checked(schema, check_device_schema, state)
        if key is None:
            continue
        if key not in state.seen_profiles:
            state.fail(schema, ProfileCheckError("device schema VID/PID has no matching controller profile"))
            continue
        if key in state.device_schemas:
            state.fail(schema, ProfileCheckError(f"duplicate device schema also in {state.device_schemas[key].name}"))
            continue
        state.device_schemas[key] = schema


def check_gip_device_schemas(state: CheckState) -> None:
    for key, (driver, hardware_verified) in sorted(state.profile_protocols.items()):
        if driver != "GIP" or not hardware_verified or key in state.device_schemas:
            continue
        profile = state.seen_profiles[key]
        state.fail(profile, ProfileCheckError("GIP controller is missing Resources/Schemas/Devices/*.json"))


def load_paths(directory: pathlib.Path, description: str) -> list[pathlib.Path]:
    paths = sorted(directory.glob("*.json"))
    if not paths:
        raise ProfileCheckError(f"no {description} found in {directory}")
    return paths


def run_checks(profiles: list[pathlib.Path], device_schemas: list[pathlib.Path]) -> int:
    state = CheckState()
    check_profiles(profiles, state)
    check_device_schemas(device_schemas, state)
    check_gip_device_schemas(state)
    if state.failures:
        print(f"FAILED: {state.failures} profile(s) invalid", file=sys.stderr)
        return 1
    print(f"Checked {len(profiles)} controller profile(s) and {len(device_schemas)} device schema(s).")
    return 0


def main() -> int:
    try:
        profiles = load_paths(PROFILE_DIR, "controller profiles")
    except ProfileCheckError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    device_schemas = sorted(DEVICE_SCHEMA_DIR.glob("*.json"))
    return run_checks(profiles, device_schemas)


if __name__ == "__main__":
    raise SystemExit(main())
