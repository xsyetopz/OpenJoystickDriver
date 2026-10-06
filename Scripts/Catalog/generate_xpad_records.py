"""Generate review-only OJD controller controller record candidates from Linux xpad.c."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILE_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/v1beta1/controller.schema.json"
)
LINUX_REPOSITORY = "torvalds/linux"
XPAD_PATH = "drivers/input/joystick/xpad.c"

DEVICE_PATTERN = re.compile(
    r"""
    \{\s*
    (?P<vid>0x[0-9a-fA-F]+)\s*,\s*
    (?P<pid>0x[0-9a-fA-F]+)\s*,\s*
    "(?P<name>(?:\\.|[^"\\])*)"\s*,\s*
    (?P<mapping>[^,]+?)\s*,\s*
    (?P<xtype>XTYPE_[A-Z0-9]+)
    (?:\s*,\s*(?P<flags>[^}]+?))?
    \s*\},
    """,
    re.VERBOSE,
)
INIT_PATTERN = re.compile(
    r"XBOXONE_INIT_PKT\(\s*(0x[0-9a-fA-F]+)\s*,\s*"
    r"(0x[0-9a-fA-F]+)\s*,\s*([A-Za-z0-9_]+)\s*\)"
)

# xpad device flags whose behavior the family's driver already performs for every row.
# `FLAG_DELAY_INIT` holds the GIP init sequence until the pad's announce packet; GIPDriver
# resends its startup sequence on the announces before the first input.
DRIVER_HANDLED_DEVICE_FLAGS = {("FLAG_DELAY_INIT", "XTYPE_XBOXONE")}
# xpad mapping macros that select a driver-declared quirk, and the one protocol
# family declaring it; rows needing a quirk their driver does not declare are skipped.
MAPPING_ORDER = (("MAP_SHARE_OFFSET", "share-offset", "xbox.gip"),)
# xpad mapping macros that remove analog controls, as capability absences in
# ControlID order. Buttons and stick clicks stay.
CAPABILITY_ABSENCES = (
    (
        "MAP_STICKS_TO_NULL",
        ("left-stick-x", "left-stick-y", "right-stick-x", "right-stick-y"),
    ),
    ("MAP_TRIGGERS_TO_BUTTONS", ("left-trigger", "right-trigger")),
)
# xpad reports these D-pad bits as buttons instead of hat axes; the wire bits
# are unchanged and OJD parsers decode them as the D-pad either way.
REPRESENTATION_MAPPING_FLAGS = {"MAP_DPAD_TO_BUTTONS"}
PRESENCE_MAPPING_FLAGS = {
    "MAP_SHARE_BUTTON",
    "MAP_PADDLES",
    "MAP_PROFILE_BUTTON",
}
DANCEPAD_FLAGS = {
    "MAP_DPAD_TO_BUTTONS",
    "MAP_TRIGGERS_TO_BUTTONS",
    "MAP_STICKS_TO_NULL",
}
INIT_PACKET_NAMES = {
    "xboxone_power_on": "xbox.gip/power-on",
    "xboxone_s_init": "xbox.gip/s-init",
    "extra_input_packet_init": "xbox.gip/enable-extra-input",
    "xboxone_hori_ack_id": "xbox.gip/hori-ack",
    "xboxone_led_on": "xbox.gip/led-on",
    "xboxone_auth_done": "xbox.gip/auth-done",
    "xboxone_rumblebegin_init": "xbox.gip/rumble-begin",
    "xboxone_rumbleend_init": "xbox.gip/rumble-end",
}
DEFAULT_INITIALIZATION = [
    "xbox.gip/power-on",
    "xbox.gip/led-on",
    "xbox.gip/auth-done",
]
# xpad type -> protocol family and stored variant (None when transport decides it).
SUPPORTED_TYPES: dict[str, tuple[str, str | None]] = {
    "XTYPE_XBOX": ("xbox.xid", "gamepad"),
    "XTYPE_XBOX360": ("xbox.xusb", "wired"),
    "XTYPE_XBOX360W": ("xbox.xusb", "receiver"),
    "XTYPE_XBOXONE": ("xbox.gip", None),
}
TYPE_FILTERS = {
    "all": None,
    "xbox.xid": "XTYPE_XBOX",
    "xbox.xusb:wired": "XTYPE_XBOX360",
    "xbox.xusb:receiver": "XTYPE_XBOX360W",
    "xbox.gip": "XTYPE_XBOXONE",
}


class GenerationError(RuntimeError):
    pass


@dataclass(frozen=True)
class XpadDevice:
    vendor_id: int
    product_id: int
    name: str
    mapping_expression: str
    xtype: str
    flags_expression: str


@dataclass(frozen=True)
class InitRule:
    vendor_id: int
    product_id: int
    source_name: str


@dataclass(frozen=True)
class Candidate:
    device: XpadDevice
    filename: str
    profile: dict[str, Any]


def extract_array(source: str, declaration: str) -> str:
    start = source.find(declaration)
    if start < 0:
        raise GenerationError(f"Could not find {declaration} in xpad source")
    opening = source.find("{", start)
    if opening < 0:
        raise GenerationError(f"Could not find opening brace for {declaration}")
    closing = source.find("\n};", opening)
    if closing < 0:
        raise GenerationError(f"Could not find closing brace for {declaration}")
    return source[opening + 1 : closing]


def decode_c_string(value: str) -> str:
    try:
        decoded = ast.literal_eval(f'"{value}"')
    except (SyntaxError, ValueError) as error:
        raise GenerationError(f"Could not decode xpad device name: {value}") from error
    return str(decoded).strip()


def parse_devices(source: str) -> list[XpadDevice]:
    table = extract_array(source, "} xpad_device[] =")
    devices: list[XpadDevice] = []
    for match in DEVICE_PATTERN.finditer(table):
        vendor_id = int(match.group("vid"), 16)
        product_id = int(match.group("pid"), 16)
        if vendor_id == 0 and product_id == 0:
            continue
        devices.append(
            XpadDevice(
                vendor_id=vendor_id,
                product_id=product_id,
                name=decode_c_string(match.group("name")),
                mapping_expression=match.group("mapping").strip(),
                xtype=match.group("xtype"),
                flags_expression=(match.group("flags") or "0").strip(),
            )
        )
    source_entries = re.findall(
        r"\{\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*,",
        table,
    )
    expected_count = sum(
        1 for vid, pid in source_entries if int(vid, 16) != 0 or int(pid, 16) != 0
    )
    if not devices:
        raise GenerationError("No xpad device entries were parsed")
    if len(devices) != expected_count:
        raise GenerationError(
            f"Parsed {len(devices)} xpad entries, but source contains "
            f"{expected_count}; refusing partial catalogue generation"
        )
    return devices


def parse_init_rules(source: str) -> list[InitRule]:
    table = extract_array(source, "xboxone_init_packets[] =")
    rules = [
        InitRule(
            vendor_id=int(match.group(1), 16),
            product_id=int(match.group(2), 16),
            source_name=match.group(3),
        )
        for match in INIT_PATTERN.finditer(table)
    ]
    expected_count = table.count("XBOXONE_INIT_PKT(")
    if not rules:
        raise GenerationError("No Xbox One initialization rules were parsed")
    if len(rules) != expected_count:
        raise GenerationError(
            f"Parsed {len(rules)} Xbox One init rules, but source contains "
            f"{expected_count}; refusing partial catalogue generation"
        )
    return rules


def parse_mapping_flags(expression: str) -> set[str]:
    normalized = expression.strip()
    if normalized == "0":
        return set()

    source_flags: set[str] = set()
    if "DANCEPAD_MAP_CONFIG" in normalized:
        source_flags.update(DANCEPAD_FLAGS)
        normalized = normalized.replace("DANCEPAD_MAP_CONFIG", "")
    source_flags.update(re.findall(r"MAP_[A-Z0-9_]+", normalized))

    known = (
        {source for source, _, _ in MAPPING_ORDER}
        | {source for source, _ in CAPABILITY_ABSENCES}
        | REPRESENTATION_MAPPING_FLAGS
        | PRESENCE_MAPPING_FLAGS
    )
    for source_name in known:
        normalized = normalized.replace(source_name, "")
    residual = re.sub(r"[\s|()]+", "", normalized)
    if residual:
        raise GenerationError(f"Unsupported mapping expression: {expression}")

    unknown = source_flags - known
    if unknown:
        raise GenerationError(
            f"Unsupported mapping flag(s): {', '.join(sorted(unknown))}"
        )
    return source_flags


def parse_device_flags(expression: str) -> list[str]:
    normalized = expression.strip()
    if normalized == "0":
        return []
    flags = re.findall(r"FLAG_[A-Z0-9_]+", normalized)
    residual = normalized
    for flag in flags:
        residual = residual.replace(flag, "")
    residual = re.sub(r"[\s|()]+", "", residual)
    if residual:
        raise GenerationError(f"Unsupported device flag expression: {expression}")
    return flags


def initialization_for(device: XpadDevice, rules: list[InitRule]) -> list[str]:
    actions: list[str] = []
    for rule in rules:
        applies_globally = rule.vendor_id == 0 and rule.product_id == 0
        applies_to_device = (
            rule.vendor_id == device.vendor_id and rule.product_id == device.product_id
        )
        if not applies_globally and not applies_to_device:
            continue
        action = INIT_PACKET_NAMES.get(rule.source_name)
        if action is None:
            raise GenerationError(
                f"Unsupported Xbox One init packet {rule.source_name} for "
                f"{device.vendor_id:04x}:{device.product_id:04x}"
            )
        actions.append(action)
    if not actions:
        raise GenerationError(
            f"No Xbox One initialization actions for {device.vendor_id:04x}:{device.product_id:04x}"
        )
    return actions


def profile_filename(device: XpadDevice) -> str:
    return f"{device.vendor_id:04x}/{device.vendor_id:04x}-{device.product_id:04x}.json"


def build_profile(
    device: XpadDevice,
    init_rules: list[InitRule],
) -> dict[str, Any]:
    family, variant = SUPPORTED_TYPES[device.xtype]
    mapping_flags = parse_mapping_flags(device.mapping_expression)
    quirks: list[str] = []
    for source, quirk, quirk_family in MAPPING_ORDER:
        if source not in mapping_flags:
            continue
        if quirk_family != family:
            raise GenerationError(f"Mapping flag {source} is not declared by {family}")
        quirks.append(quirk)
    absent = [
        control
        for source, controls in CAPABILITY_ABSENCES
        if source in mapping_flags
        for control in controls
    ]

    protocol: dict[str, Any] = {"family": family}
    if variant is not None:
        protocol["variant"] = variant
    if quirks:
        protocol["quirks"] = quirks
    if family == "xbox.gip":
        initialization = initialization_for(device, init_rules)
        if initialization != DEFAULT_INITIALIZATION:
            protocol["initialization"] = initialization

    profile: dict[str, Any] = {
        "$schema": SCHEMA_ID,
        "vendorID": device.vendor_id,
        "productID": device.product_id,
        "protocol": protocol,
    }
    if absent:
        profile["capabilities"] = {"absent": absent}
    return profile


def load_existing_profile_keys() -> set[tuple[int, int]]:
    keys: set[tuple[int, int]] = set()
    for path in sorted(PROFILE_DIR.glob("*/*.json")):
        try:
            document = json.loads(path.read_text())
            keys.add((int(document["vendorID"]), int(document["productID"])))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise GenerationError(
                f"Could not read bundled record {path}: {error}"
            ) from error
    return keys


def generate_candidates(
    devices: list[XpadDevice],
    init_rules: list[InitRule],
    existing_keys: set[tuple[int, int]],
    include_existing: bool,
    requested_type: str,
    vendor_id: int | None,
    product_id: int | None,
) -> tuple[list[Candidate], list[dict[str, Any]], int]:
    target_type = TYPE_FILTERS[requested_type]
    candidates: list[Candidate] = []
    skipped: list[dict[str, Any]] = []
    filtered_out = 0

    for device in devices:
        if target_type is not None and device.xtype != target_type:
            filtered_out += 1
            continue
        if vendor_id is not None and device.vendor_id != vendor_id:
            filtered_out += 1
            continue
        if product_id is not None and device.product_id != product_id:
            filtered_out += 1
            continue

        reason: str | None = None
        if device.vendor_id == 0xFFFF and device.product_id == 0xFFFF:
            reason = "linux_catchall_identity"
        elif device.xtype not in SUPPORTED_TYPES:
            reason = f"unsupported_type:{device.xtype}"
        elif (
            not include_existing
            and (device.vendor_id, device.product_id) in existing_keys
        ):
            reason = "already_bundled"
        else:
            try:
                device_flags = [
                    flag
                    for flag in parse_device_flags(device.flags_expression)
                    if (flag, device.xtype) not in DRIVER_HANDLED_DEVICE_FLAGS
                ]
                if device_flags:
                    reason = f"unsupported_device_flags:{','.join(device_flags)}"
                else:
                    profile = build_profile(device, init_rules)
                    candidates.append(
                        Candidate(
                            device=device,
                            filename=profile_filename(device),
                            profile=profile,
                        )
                    )
            except GenerationError as error:
                reason = str(error)

        if reason is not None:
            skipped.append(
                {
                    "vendorID": device.vendor_id,
                    "productID": device.product_id,
                    "name": device.name,
                    "xtype": device.xtype,
                    "reason": reason,
                }
            )

    candidates.sort(key=lambda item: (item.device.vendor_id, item.device.product_id))
    skipped.sort(key=lambda item: (item["vendorID"], item["productID"]))
    return candidates, skipped, filtered_out


from Scripts.Catalog.xpad_io import (
    load_github_source,
    load_local_source,
    write_catalog,
)


def parse_cli_int(value: str) -> int:
    try:
        parsed = int(value, 0)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid integer: {value}") from error
    if not 0 <= parsed <= 65_535:
        raise argparse.ArgumentTypeError("VID/PID must be in 0...65535")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate review-only OJD controller record candidates from a pinned Linux xpad.c source"
        )
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--source", type=pathlib.Path, help="local xpad.c path")
    source.add_argument(
        "--github-ref",
        help="Linux GitHub ref to resolve and pin, for example master or a commit SHA",
    )
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument("--type", choices=sorted(TYPE_FILTERS), default="all")
    parser.add_argument("--vid", type=parse_cli_int)
    parser.add_argument("--pid", type=parse_cli_int)
    parser.add_argument(
        "--include-existing",
        action="store_true",
        help="also emit candidates whose VID:PID is already bundled",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite differing generated files after explicit review",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.github_ref is not None:
            source, source_info = load_github_source(args.github_ref, GenerationError)
        else:
            source, source_info = load_local_source(args.source)

        devices = parse_devices(source)
        init_rules = parse_init_rules(source)
        candidates, skipped, filtered_out = generate_candidates(
            devices=devices,
            init_rules=init_rules,
            existing_keys=load_existing_profile_keys(),
            include_existing=args.include_existing,
            requested_type=args.type,
            vendor_id=args.vid,
            product_id=args.pid,
        )
        source_info["sha256"] = hashlib.sha256(source.encode()).hexdigest()
        write_catalog(
            args.output_dir, candidates, force=args.force, failure=GenerationError
        )
    except (GenerationError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(
        f"Generated {len(candidates)} controller record candidate(s) in {args.output_dir} "
        f"({len(skipped)} skipped, {filtered_out} filtered out)"
    )
    print(f"Source SHA-256: {source_info['sha256']}")
    if source_info["commit"]:
        print(f"Linux commit: {source_info['commit']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
