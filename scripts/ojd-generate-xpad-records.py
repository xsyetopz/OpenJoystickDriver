#!/usr/bin/env python3
"""Generate review-only OJD controller controller record candidates from Linux xpad.c."""

from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller.schema.json"
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

MAPPING_ORDER = (
    ("MAP_DPAD_TO_BUTTONS", "dpadToButtons"),
    ("MAP_TRIGGERS_TO_BUTTONS", "triggersToButtons"),
    ("MAP_STICKS_TO_NULL", "sticksToNull"),
    ("MAP_SHARE_BUTTON", "shareButton"),
    ("MAP_PADDLES", "paddles"),
    ("MAP_PROFILE_BUTTON", "profileButton"),
    ("MAP_SHARE_OFFSET", "shareOffset"),
)
DANCEPAD_FLAGS = {
    "MAP_DPAD_TO_BUTTONS",
    "MAP_TRIGGERS_TO_BUTTONS",
    "MAP_STICKS_TO_NULL",
}
INIT_PACKET_NAMES = {
    "xboxone_power_on": "powerOn",
    "xboxone_s_init": "xboxOneSInit",
    "extra_input_packet_init": "extraInput",
    "xboxone_hori_ack_id": "horiAck",
    "xboxone_led_on": "ledOn",
    "xboxone_auth_done": "authDone",
    "xboxone_rumblebegin_init": "rumbleBegin",
    "xboxone_rumbleend_init": "rumbleEnd",
}
SUPPORTED_TYPES = {
    "XTYPE_XBOX360": ("Xbox360", "xbox360", 129, 1),
    "XTYPE_XBOX360W": ("Xbox360", "xbox360Wireless", 129, 1),
    "XTYPE_XBOXONE": ("GIP", "xboxOne", 130, 2),
}
TYPE_FILTERS = {
    "all": None,
    "xbox360": "XTYPE_XBOX360",
    "xbox360Wireless": "XTYPE_XBOX360W",
    "xboxOne": "XTYPE_XBOXONE",
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


def parse_mapping_flags(expression: str) -> list[str]:
    normalized = expression.strip()
    if normalized == "0":
        return []

    source_flags: set[str] = set()
    if "DANCEPAD_MAP_CONFIG" in normalized:
        source_flags.update(DANCEPAD_FLAGS)
        normalized = normalized.replace("DANCEPAD_MAP_CONFIG", "")
    source_flags.update(re.findall(r"MAP_[A-Z0-9_]+", normalized))

    for source_name, _ in MAPPING_ORDER:
        normalized = normalized.replace(source_name, "")
    residual = re.sub(r"[\s|()]+", "", normalized)
    if residual:
        raise GenerationError(f"Unsupported mapping expression: {expression}")

    known = {source for source, _ in MAPPING_ORDER}
    unknown = source_flags - known
    if unknown:
        raise GenerationError(
            f"Unsupported mapping flag(s): {', '.join(sorted(unknown))}"
        )
    return [target for source, target in MAPPING_ORDER if source in source_flags]


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


def startup_packets_for(device: XpadDevice, rules: list[InitRule]) -> list[str]:
    packets: list[str] = []
    for rule in rules:
        applies_globally = rule.vendor_id == 0 and rule.product_id == 0
        applies_to_device = (
            rule.vendor_id == device.vendor_id and rule.product_id == device.product_id
        )
        if not applies_globally and not applies_to_device:
            continue
        packet = INIT_PACKET_NAMES.get(rule.source_name)
        if packet is None:
            raise GenerationError(
                f"Unsupported Xbox One init packet {rule.source_name} for "
                f"{device.vendor_id:04x}:{device.product_id:04x}"
            )
        packets.append(packet)
    if not packets:
        raise GenerationError(
            f"No Xbox One startup packets for {device.vendor_id:04x}:{device.product_id:04x}"
        )
    return packets


def profile_filename(device: XpadDevice) -> str:
    return f"{device.vendor_id:04x}/{device.vendor_id:04x}-{device.product_id:04x}.json"


def build_profile(
    device: XpadDevice,
    init_rules: list[InitRule],
) -> dict[str, Any]:
    driver, variant, _, _ = SUPPORTED_TYPES[device.xtype]
    mapping_flags = parse_mapping_flags(device.mapping_expression)
    allowed_flags = (
        {"dpadToButtons", "triggersToButtons", "sticksToNull"}
        if driver == "Xbox360"
        else {
            "dpadToButtons", "triggersToButtons", "sticksToNull",
            "shareButton", "paddles", "profileButton", "shareOffset",
        }
    )
    unsupported_flags = set(mapping_flags) - allowed_flags
    if unsupported_flags:
        raise GenerationError(
            f"Mapping flags invalid for {driver}: {', '.join(sorted(unsupported_flags))}"
        )

    protocol: dict[str, Any] = {"driver": driver, "variant": variant}
    if mapping_flags:
        protocol["flags"] = mapping_flags
    if driver == "GIP":
        startup_packets = startup_packets_for(device, init_rules)
        if startup_packets != ["powerOn", "ledOn", "authDone"]:
            protocol["startup_packets"] = startup_packets

    return {
        "$schema": SCHEMA_ID,
        "vendor_id": device.vendor_id,
        "product_id": device.product_id,
        "transport": "usb",
        "protocol": protocol,
        "provenance": {"source": "linux-xpad.c", "verified": False},
    }


def load_existing_profile_keys() -> set[tuple[int, int]]:
    keys: set[tuple[int, int]] = set()
    for path in sorted(PROFILE_DIR.glob("*/*.json")):
        try:
            document = json.loads(path.read_text())
            keys.add((int(document["vendor_id"]), int(document["product_id"])))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise GenerationError(f"Could not read bundled record {path}: {error}") from error
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
        if device.xtype not in SUPPORTED_TYPES:
            reason = f"unsupported_type:{device.xtype}"
        elif (
            not include_existing
            and (device.vendor_id, device.product_id) in existing_keys
        ):
            reason = "already_bundled"
        else:
            try:
                device_flags = parse_device_flags(device.flags_expression)
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
                    "vendor_id": device.vendor_id,
                    "product_id": device.product_id,
                    "name": device.name,
                    "xtype": device.xtype,
                    "reason": reason,
                }
            )

    candidates.sort(key=lambda item: (item.device.vendor_id, item.device.product_id))
    skipped.sort(key=lambda item: (item["vendor_id"], item["product_id"]))
    return candidates, skipped, filtered_out


def run_gh(args: list[str]) -> str:
    command = ["gh", *args]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise GenerationError(f"{' '.join(command)} failed: {detail}")
    return result.stdout


def load_github_source(ref: str) -> tuple[str, dict[str, Any]]:
    encoded_ref = urllib.parse.quote(ref, safe="")
    commit_document = json.loads(
        run_gh(["api", f"repos/{LINUX_REPOSITORY}/commits/{encoded_ref}"])
    )
    commit = str(commit_document["sha"])
    source_document = json.loads(
        run_gh(
            [
                "api",
                "-X",
                "GET",
                f"repos/{LINUX_REPOSITORY}/contents/{XPAD_PATH}",
                "-f",
                f"ref={commit}",
            ]
        )
    )
    source = base64.b64decode(source_document["content"]).decode()
    return source, {
        "kind": "github",
        "repository": LINUX_REPOSITORY,
        "path": XPAD_PATH,
        "requested_ref": ref,
        "commit": commit,
    }


def load_local_source(path: pathlib.Path) -> tuple[str, dict[str, Any]]:
    source = path.read_text()
    return source, {
        "kind": "local",
        "repository": LINUX_REPOSITORY,
        "path": str(path.resolve()),
        "requested_ref": None,
        "commit": None,
    }


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def write_output(path: pathlib.Path, content: str, force: bool) -> None:
    if path.exists():
        current = path.read_text()
        if current == content:
            return
        if not force:
            raise GenerationError(
                f"Refusing to overwrite different file {path}; pass --force after review"
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def write_catalog(
    output_dir: pathlib.Path,
    candidates: list[Candidate],
    manifest: dict[str, Any],
    force: bool,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    planned = {
        output_dir / candidate.filename: json_text(candidate.profile)
        for candidate in candidates
    }
    planned[output_dir / "manifest.json"] = json_text(manifest)

    if not force:
        conflicts = [
            path
            for path, content in planned.items()
            if path.exists() and path.read_text() != content
        ]
        if conflicts:
            names = ", ".join(str(path) for path in conflicts)
            raise GenerationError(
                f"Refusing to overwrite different file(s): {names}; "
                "pass --force after review"
            )

    for path, content in planned.items():
        write_output(path, content, force=force)


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
            source, source_info = load_github_source(args.github_ref)
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
        manifest = {
            "schema_version": 1,
            "source": source_info,
            "selection": {
                "type": args.type,
                "vendor_id": args.vid,
                "product_id": args.pid,
                "include_existing": args.include_existing,
            },
            "counts": {
                "source_devices": len(devices),
                "filtered_out": filtered_out,
                "profiles": len(candidates),
                "skipped": len(skipped),
            },
            "assumptions": [
                "Generated records are review-only and provenance.verified is false.",
                "Xbox 360 wired and wireless-receiver endpoints default to IN 129 and OUT 1.",
                "Xbox One wired endpoints default to IN 130 and OUT 2.",
                "Endpoint, interface, startup, input, rumble, and LED behavior require hardware validation.",
                "Original Xbox, unknown types, delayed init, and unknown source macros are skipped.",
            ],
            "profiles": [
                {
                    "file": item.filename,
                    "vendor_id": item.device.vendor_id,
                    "product_id": item.device.product_id,
                    "name": item.device.name,
                    "xtype": item.device.xtype,
                }
                for item in candidates
            ],
            "skipped": skipped,
        }
        write_catalog(args.output_dir, candidates, manifest, force=args.force)
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
