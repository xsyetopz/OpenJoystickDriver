#!/usr/bin/env python3
"""Rebuild the runtime controller catalog from pinned sources and local overrides."""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import pathlib
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "ControllerSources.lock.json"
OVERRIDE_DIR = ROOT / "Resources" / "ControllerOverrides"
OUTPUT_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"



HID_RECORDS = (
    ("hid_sony", "USB_VENDOR_ID_SONY", "USB_DEVICE_ID_SONY_PS3_CONTROLLER",
     "DS3", "dualShock3", ["experimental", "needsHardwareTest"], "linux-hid-sony.c"),
    ("hid_playstation", "USB_VENDOR_ID_SONY", "USB_DEVICE_ID_SONY_PS4_CONTROLLER",
     "DS4", "dualShock4", [], "linux-hid-playstation.c"),
    ("hid_playstation", "USB_VENDOR_ID_SONY", "USB_DEVICE_ID_SONY_PS4_CONTROLLER_2",
     "DS4", "dualShock4", [], "linux-hid-playstation.c"),
    ("hid_playstation", "USB_VENDOR_ID_SONY", "USB_DEVICE_ID_SONY_PS5_CONTROLLER",
     "DualSense", "dualSense", ["touchpad", "microphoneMute", "experimental", "needsHardwareTest"],
     "linux-hid-playstation.c"),
    ("hid_playstation", "USB_VENDOR_ID_SONY", "USB_DEVICE_ID_SONY_PS5_CONTROLLER_2",
     "DualSense", "dualSense", ["touchpad", "microphoneMute", "experimental", "needsHardwareTest"],
     "linux-hid-playstation.c"),
    ("hid_nintendo", "USB_VENDOR_ID_NINTENDO", "USB_DEVICE_ID_NINTENDO_PROCON",
     "SwitchPro", "switchPro", ["usbHandshake", "experimental", "needsHardwareTest"],
     "linux-hid-nintendo.c"),
    ("hid_steam", "USB_VENDOR_ID_VALVE", "USB_DEVICE_ID_STEAM_CONTROLLER",
     "SteamController", "steamController", ["lizardMode", "trackpads", "experimental", "needsHardwareTest"],
     "linux-hid-steam.c"),
    ("hid_steam", "USB_VENDOR_ID_VALVE", "USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS",
     "SteamController", "steamController",
     ["lizardMode", "trackpads", "wirelessReceiver", "experimental", "needsHardwareTest"],
     "linux-hid-steam.c"),
)


def load_locked_linux_files(generator: Any, linux: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, file_lock in sorted(linux["files"].items()):
        url = (
            f"https://raw.githubusercontent.com/{linux['repository']}/"
            f"{linux['commit']}/{file_lock['path']}"
        )
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "OpenJoystickDriver-catalog"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                source = response.read().decode()
        except urllib.error.HTTPError:
            document = json.loads(generator.run_gh([
                "api", "-X", "GET",
                f"repos/{linux['repository']}/contents/{file_lock['path']}",
                "-f", f"ref={linux['commit']}",
            ]))
            source = base64.b64decode(document["content"]).decode()
        digest = hashlib.sha256(source.encode()).hexdigest()
        if digest != file_lock["sha256"]:
            raise CatalogError(
                f"{key} source hash mismatch: expected {file_lock['sha256']}, got {digest}"
            )
        result[key] = source
    return result


def parse_defines(source: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^#define\s+([A-Z0-9_]+)\s+(0x[0-9a-fA-F]+)\s*$",
            source,
            re.MULTILINE,
        )
    }


def build_hid_records(sources: dict[str, str]) -> list[dict[str, Any]]:
    defines = parse_defines(sources["hid_ids"])
    records: list[dict[str, Any]] = []
    for source_key, vendor_macro, product_macro, driver, variant, flags, provenance in HID_RECORDS:
        source = sources[source_key]
        pattern = (
            r"HID_(?:USB|BLUETOOTH)_DEVICE\s*\(\s*"
            + re.escape(vendor_macro)
            + r"\s*,\s*"
            + re.escape(product_macro)
            + r"\s*\)"
        )
        if re.search(pattern, source) is None:
            raise CatalogError(
                f"{source_key} no longer registers {vendor_macro}/{product_macro}"
            )
        try:
            vendor_id = defines[vendor_macro]
            product_id = defines[product_macro]
        except KeyError as error:
            raise CatalogError(f"missing Linux HID ID definition: {error}") from error
        protocol: dict[str, Any] = {"driver": driver, "variant": variant}
        if flags:
            protocol["flags"] = flags
        records.append({
            "$schema": (
                "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
                "Resources/Schemas/controller.schema.json"
            ),
            "vendor_id": vendor_id,
            "product_id": product_id,
            "transport": "hid",
            "protocol": protocol,
            "provenance": {"source": provenance, "verified": False},
        })
    return records

class CatalogError(RuntimeError):
    pass


def load_module(name: str, path: pathlib.Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise CatalogError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def record_key(record: dict[str, Any]) -> tuple[int, int]:
    return int(record["vendor_id"]), int(record["product_id"])


def record_path(root: pathlib.Path, key: tuple[int, int]) -> pathlib.Path:
    vendor_id, product_id = key
    return root / f"{vendor_id:04x}" / f"{vendor_id:04x}-{product_id:04x}.json"


def load_lock() -> dict[str, Any]:
    try:
        lock = json.loads(LOCK_PATH.read_text())
        linux = lock["linux"]
        xpad = linux["files"]["xpad"]
        if linux["repository"] != "torvalds/linux":
            raise CatalogError("unsupported Linux repository")
        if len(linux["commit"]) != 40:
            raise CatalogError("Linux commit must be a full SHA")
        if len(xpad["sha256"]) != 64:
            raise CatalogError("xpad SHA-256 is invalid")
        return lock
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise CatalogError(f"invalid {LOCK_PATH.name}: {error}") from error


def load_overrides(
    validator: Any,
    override_dir: pathlib.Path = OVERRIDE_DIR,
) -> list[tuple[str, tuple[int, int], dict[str, Any]]]:
    result: list[tuple[str, tuple[int, int], dict[str, Any]]] = []
    seen: set[tuple[int, int]] = set()
    schema_id = (
        "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
        "Resources/Schemas/controller-override.schema.json"
    )
    for path in sorted(override_dir.glob("*/*.json")):
        document = json.loads(path.read_text())
        if document.get("$schema") != schema_id:
            raise CatalogError(f"{path}: invalid override schema")
        operation = document.get("operation")
        allowed = (
            {"$schema", "operation", "record"}
            if operation == "add"
            else {"$schema", "operation", "vendor_id", "product_id", "set"}
        )
        if operation not in {"add", "patch"} or set(document) != allowed:
            raise CatalogError(f"{path}: invalid override shape")
        if operation == "add":
            record = document["record"]
            temporary = path.with_name(".record-validation.json")
            temporary.write_text(json.dumps(record))
            try:
                validator.validate_record(temporary, enforce_path=False)
            finally:
                temporary.unlink(missing_ok=True)
            key = record_key(record)
            payload = record
        else:
            key = (int(document["vendor_id"]), int(document["product_id"]))
            payload = document["set"]
            if not payload or not set(payload) <= {"transport", "protocol", "usb", "provenance"}:
                raise CatalogError(f"{path}: invalid patch fields")
        expected = record_path(override_dir, key)
        if path != expected:
            raise CatalogError(f"{path}: override path must be {expected}")
        if key in seen:
            raise CatalogError(f"{path}: duplicate override for {key}")
        seen.add(key)
        result.append((operation, key, payload))
    return result


def apply_overrides(
    records: dict[tuple[int, int], dict[str, Any]],
    overrides: list[tuple[str, tuple[int, int], dict[str, Any]]],
) -> None:
    for operation, key, payload in overrides:
        upstream = records.get(key)
        if operation == "add":
            if upstream is not None:
                raise CatalogError(f"add override conflicts with upstream identity {key}")
            records[key] = payload
            continue
        if upstream is None:
            raise CatalogError(f"orphan patch override for {key}")
        merged = {**upstream, **payload}
        if merged == upstream:
            raise CatalogError(f"redundant patch override for {key}")
        source_name = merged["provenance"]["source"]
        if source_name not in {"local-hardware", "tester-packets"}:
            raise CatalogError(f"patch override for {key} requires local evidence")
        records[key] = merged


def build_catalog() -> dict[tuple[int, int], dict[str, Any]]:
    generator = load_module(
        "ojd_generate_xpad_records",
        ROOT / "scripts" / "catalog" / "generate-xpad-records.py",
    )
    validator = load_module(
        "ojd_validate_profiles",
        ROOT / "scripts" / "catalog" / "validate-profiles.py",
    )
    lock = load_lock()
    linux = lock["linux"]
    xpad_lock = linux["files"]["xpad"]

    sources = load_locked_linux_files(generator, linux)
    source = sources["xpad"]
    candidates, skipped, _ = generator.generate_candidates(
        devices=generator.parse_devices(source),
        init_rules=generator.parse_init_rules(source),
        existing_keys=set(),
        include_existing=True,
        requested_type="all",
        vendor_id=None,
        product_id=None,
    )
    records: dict[tuple[int, int], dict[str, Any]] = {}
    for candidate in candidates:
        key = (candidate.device.vendor_id, candidate.device.product_id)
        if key in records:
            raise CatalogError(f"Linux source produced duplicate identity {key}")
        records[key] = candidate.profile
    for record in build_hid_records(sources):
        key = record_key(record)
        if key in records:
            raise CatalogError(f"Linux sources produced duplicate identity {key}")
        records[key] = record

    apply_overrides(records, load_overrides(validator))

    if not records:
        raise CatalogError("generation produced no controller records")

    with tempfile.TemporaryDirectory() as directory:
        temporary_root = pathlib.Path(directory)
        for key, record in sorted(records.items()):
            path = record_path(temporary_root, key)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(generator.json_text(record))
            validator.validate_record(path, enforce_path=False)

    if skipped:
        print(f"Linux rows intentionally skipped: {len(skipped)}")
    return records


def expected_files(records: dict[tuple[int, int], dict[str, Any]]) -> dict[pathlib.Path, str]:
    return {
        record_path(OUTPUT_DIR, key): json.dumps(record, indent=2, ensure_ascii=False) + "\n"
        for key, record in sorted(records.items())
    }


def check_catalog(records: dict[tuple[int, int], dict[str, Any]]) -> None:
    expected = expected_files(records)
    actual = set(OUTPUT_DIR.glob("*/*.json"))
    missing = sorted(set(expected) - actual)
    stale = sorted(actual - set(expected))
    changed = sorted(path for path, text in expected.items() if path.exists() and path.read_text() != text)
    if missing or stale or changed:
        details = [
            *(f"missing {path.relative_to(ROOT)}" for path in missing),
            *(f"stale {path.relative_to(ROOT)}" for path in stale),
            *(f"changed {path.relative_to(ROOT)}" for path in changed),
        ]
        raise CatalogError("catalog differs from generated output:\n" + "\n".join(details))


def write_catalog(records: dict[tuple[int, int], dict[str, Any]]) -> None:
    expected = expected_files(records)
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    for path, text in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        records = build_catalog()
        if args.check:
            check_catalog(records)
            verb = "Verified"
        else:
            write_catalog(records)
            verb = "Generated"
    except (CatalogError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"{verb} {len(records)} canonical controller record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
