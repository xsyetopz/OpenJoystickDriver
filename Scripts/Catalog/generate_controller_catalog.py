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

from Scripts.Catalog.xpad_io import json_text, run_gh

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "ControllerSources.lock.json"
OVERRIDE_DIR = ROOT / "Resources" / "ControllerOverrides"
OUTPUT_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
RECORD_SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller.schema.json"
)


# DualSense Edge function buttons and back paddles, present beyond the DualSense
# family defaults (Linux hid-playstation registers the Edge separately).
DUALSENSE_EDGE_CAPABILITIES: dict[str, Any] = {
    "present": ["paddle-left-1", "paddle-right-1", "auxiliary-1", "auxiliary-2"]
}

# (source, vendor macro, product macro, family, stored variant, quirks, capabilities)
HID_RECORDS: tuple[
    tuple[str, str, str, str, str | None, list[str], dict[str, Any] | None], ...
] = (
    (
        "hid_sony",
        "USB_VENDOR_ID_SONY",
        "USB_DEVICE_ID_SONY_PS3_CONTROLLER",
        "sony.sixaxis",
        None,
        [],
        None,
    ),
    (
        "hid_playstation",
        "USB_VENDOR_ID_SONY",
        "USB_DEVICE_ID_SONY_PS4_CONTROLLER",
        "sony.dualshock4",
        None,
        [],
        None,
    ),
    (
        "hid_playstation",
        "USB_VENDOR_ID_SONY",
        "USB_DEVICE_ID_SONY_PS4_CONTROLLER_2",
        "sony.dualshock4",
        None,
        [],
        None,
    ),
    (
        "hid_playstation",
        "USB_VENDOR_ID_SONY",
        "USB_DEVICE_ID_SONY_PS5_CONTROLLER",
        "sony.dualsense",
        None,
        [],
        None,
    ),
    (
        "hid_playstation",
        "USB_VENDOR_ID_SONY",
        "USB_DEVICE_ID_SONY_PS5_CONTROLLER_2",
        "sony.dualsense",
        None,
        [],
        DUALSENSE_EDGE_CAPABILITIES,
    ),
    (
        "hid_nintendo",
        "USB_VENDOR_ID_NINTENDO",
        "USB_DEVICE_ID_NINTENDO_PROCON",
        "nintendo.switch1",
        None,
        [],
        None,
    ),
    (
        "hid_nintendo",
        "USB_VENDOR_ID_NINTENDO",
        "USB_DEVICE_ID_NINTENDO_JOYCONL",
        "nintendo.switch1",
        None,
        ["joy-con-left"],
        None,
    ),
    (
        "hid_nintendo",
        "USB_VENDOR_ID_NINTENDO",
        "USB_DEVICE_ID_NINTENDO_JOYCONR",
        "nintendo.switch1",
        None,
        ["joy-con-right"],
        None,
    ),
    (
        "hid_steam",
        "USB_VENDOR_ID_VALVE",
        "USB_DEVICE_ID_STEAM_CONTROLLER",
        "valve.steam-controller",
        "wired",
        [],
        None,
    ),
    (
        "hid_steam",
        "USB_VENDOR_ID_VALVE",
        "USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS",
        "valve.steam-controller",
        "dongle",
        [],
        None,
    ),
)


def load_locked_files(source_lock: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, file_lock in sorted(source_lock["files"].items()):
        url = (
            f"https://raw.githubusercontent.com/{source_lock['repository']}/"
            f"{source_lock['commit']}/{file_lock['path']}"
        )
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "OpenJoystickDriver-catalog"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                source = response.read().decode()
        except urllib.error.HTTPError:
            document = json.loads(
                run_gh(
                    [
                        "api",
                        "-X",
                        "GET",
                        f"repos/{source_lock['repository']}/contents/{file_lock['path']}",
                        "-f",
                        f"ref={source_lock['commit']}",
                    ],
                    CatalogError,
                )
            )
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
    for (
        source_key,
        vendor_macro,
        product_macro,
        family,
        variant,
        quirks,
        capabilities,
    ) in HID_RECORDS:
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
        protocol: dict[str, Any] = {"family": family}
        if variant is not None:
            protocol["variant"] = variant
        if quirks:
            protocol["quirks"] = quirks
        record: dict[str, Any] = {
            "$schema": RECORD_SCHEMA_ID,
            "vendorID": vendor_id,
            "productID": product_id,
            "protocol": protocol,
        }
        if capabilities is not None:
            record["capabilities"] = capabilities
        records.append(record)
    return records


SONY_VENDOR_ID = 0x054C
MICROSOFT_VENDOR_ID = 0x045E
NVIDIA_VENDOR_ID = 0x0955
# Microsoft Xbox 360 product IDs (wired pad, receivers, Big Button IR, Windows
# driver identity). Third-party XBoxOneController rows reuse them.
MICROSOFT_XBOX_360_PRODUCT_IDS = frozenset(
    {0x028E, 0x0291, 0x02A0, 0x02A1, 0x02A9, 0x0719}
)

# SDL controller type -> (family, stored variant). Types absent here have no
# implemented family and are skipped. Steam rows take their variant from
# STEAM_VARIANTS, because one SDL type covers wired pads, dongles and Bluetooth LE links.
SDL_FAMILIES: dict[str, tuple[str, str | None]] = {
    "PS3Controller": ("sony.sixaxis", None),
    "PS4Controller": ("sony.dualshock4", None),
    "PS5Controller": ("sony.dualsense", None),
    "SwitchProController": ("nintendo.switch1", None),
    "SwitchJoyConLeft": ("nintendo.switch1", None),
    "SwitchJoyConRight": ("nintendo.switch1", None),
    "XBox360Controller": ("xbox.xusb", "wired"),
    "XBoxOneController": ("xbox.gip", None),
    "SteamController": ("valve.steam-controller", None),
    "SteamControllerV2": ("valve.steam-controller", None),
    "SteamControllerNeptune": ("valve.steam-controller", None),
    "SwitchInputOnlyController": ("nintendo.switch1", None),
    "SteamControllerTriton": ("valve.steam-controller", None),
}

# Stored variant of each Valve Steam identity, from the per-row comments in SDL
# `controller_list.h` ("wired", "Bluetooth", "BLE", "Dongle") and SDL `IsDongle` /
# `IsProteusDongle`. A Steam row missing here fails generation instead of guessing.
STEAM_VARIANTS: dict[tuple[int, int], str] = {
    (0x28DE, 0x1101): "wired",  # Legacy Steam Controller (CHELL)
    (0x28DE, 0x1102): "wired",  # wired Steam Controller (D0G)
    (0x28DE, 0x1105): "bluetooth-le",  # Bluetooth Steam Controller (D0G)
    (0x28DE, 0x1106): "bluetooth-le",  # Bluetooth Steam Controller (D0G)
    (0x28DE, 0x1142): "dongle",  # wireless Steam Controller
    (0x28DE, 0x1201): "wired",  # wired Steam Controller (HEADCRAB)
    (0x28DE, 0x1202): "bluetooth-le",  # Bluetooth Steam Controller (HEADCRAB)
    (0x28DE, 0x1205): "wired",  # Steam Deck built-in controller
    (0x28DE, 0x1302): "wired",  # Steam Triton Controller
    (0x28DE, 0x1303): "bluetooth-le",  # Steam Triton Controller (BLE)
    (0x28DE, 0x1304): "dongle",  # Steam Proteus Dongle
    (0x28DE, 0x1305): "dongle",  # Steam Nereid Dongle
}

# SDL controller type -> quirks its rows carry. SwitchInputOnlyController pads send one fixed HID
# report and take no Switch subcommands; SteamControllerTriton selects the Triton driver and
# SteamControllerNeptune the Steam Deck driver. The Joy-Con types select the Joy-Con side.
SDL_QUIRKS: dict[str, list[str]] = {
    "SwitchJoyConLeft": ["joy-con-left"],
    "SwitchJoyConRight": ["joy-con-right"],
    "SwitchInputOnlyController": ["input-only"],
    "SteamControllerTriton": ["triton"],
    "SteamControllerNeptune": ["neptune"],
}

# Nintendo Switch 2 identities, from the SDL `USB_PRODUCT_NINTENDO_SWITCH2_*` IDs that
# `SDL_hidapi_switch2.c` claims. SDL lists them under the Switch 1 types, so their rows also
# carry the Switch 2 quirk before any Joy-Con side quirk.
SWITCH_2_IDENTITIES = frozenset({(0x057E, 0x2066), (0x057E, 0x2067), (0x057E, 0x2069)})

# Identities whose SDL type does not describe the wire protocol of an implemented
# variant: (identity) -> (expected SDL type, skip reason). Each entry must still be
# listed with that type at the pinned commit and must not already be catalogued.
SDL_EXCLUSIONS: dict[tuple[int, int], tuple[str, str]] = {
    (0x045E, 0x02A0): ("XBox360Controller", "xbox-360-receiver"),
    (0x045E, 0x02A1): ("XBox360Controller", "windows-driver-identity"),
    (0x045E, 0x02FF): ("XBoxOneController", "windows-driver-identity"),
    (0x045E, 0x02E0): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x02FD): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B05): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B0C): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B13): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B20): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B21): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0B22): ("XBoxOneController", "xbox-bluetooth"),
    (0x045E, 0x0867): ("XBoxOneController", "semantics-unclear"),
    (0x054C, 0x05C5): ("PS4Controller", "grip-add-on"),
    (0x054C, 0x0BA0): ("PS4Controller", "ds4-dongle"),
    (0x054C, 0x0E5F): ("PS5Controller", "layout-unverified"),
    (0x0E6F, 0x0186): ("SwitchProController", "no-usb-protocol"),
    (0x0F0D, 0x00F6): ("SwitchProController", "no-usb-protocol"),
    (0x1038, 0xB360): ("XBox360Controller", "semantics-unclear"),
}

SDL_ARRAY_PATTERN = re.compile(
    r"arrControllers\[\]\s*=\s*\{(?P<body>.*?)^\};", re.DOTALL | re.MULTILINE
)
SDL_ENTRY_PATTERN = re.compile(
    r"""
    \{\s*MAKE_CONTROLLER_ID\s*\(\s*
    (?P<vid>0[xX][0-9a-fA-F]+)\s*,\s*
    (?P<pid>0[xX][0-9a-fA-F]+)\s*\)\s*,\s*
    k_eControllerType_(?P<type>\w+)\s*,\s*
    (?:NULL|"(?:\\.|[^"\\])*")\s*
    \}\s*,\s*(?://.*)?
    """,
    re.VERBOSE,
)


def parse_sdl_controllers(source: str) -> list[tuple[int, int, str]]:
    """Returns (vendor ID, product ID, SDL type) for every active arrControllers row."""
    match = SDL_ARRAY_PATTERN.search(source)
    if match is None:
        raise CatalogError("SDL controller_list.h has no arrControllers table")
    rows: list[tuple[int, int, str]] = []
    for line in match["body"].splitlines():
        text = line.strip()
        if not text or text.startswith("//"):
            continue
        entry = SDL_ENTRY_PATTERN.fullmatch(text)
        if entry is None:
            raise CatalogError(f"unparsed SDL controller_list.h row: {text}")
        rows.append((int(entry["vid"], 16), int(entry["pid"], 16), entry["type"]))
    if not rows:
        raise CatalogError("SDL controller_list.h produced no rows")
    return rows


def sdl_rule_reason(key: tuple[int, int], controller_type: str) -> str | None:
    vendor_id, product_id = key
    if vendor_id == 0:
        return "not-usb-identity"
    if controller_type == "PS3Controller" and vendor_id != SONY_VENDOR_ID:
        return "third-party-ps3"
    if controller_type == "PS5Controller" and vendor_id != SONY_VENDOR_ID:
        return "third-party-ps5"
    if controller_type == "XBox360Controller" and vendor_id == NVIDIA_VENDOR_ID:
        return "not-xbox-protocol"
    if (
        controller_type == "XBoxOneController"
        and product_id in MICROSOFT_XBOX_360_PRODUCT_IDS
    ):
        return "xbox-360-product-id"
    return None


def sdl_skip_reason(key: tuple[int, int], controller_type: str) -> str | None:
    rule = sdl_rule_reason(key, controller_type)
    exclusion = SDL_EXCLUSIONS.get(key)
    if exclusion is not None:
        if rule is not None:
            raise CatalogError(f"redundant SDL exclusion {key}: rule {rule} applies")
        return exclusion[1]
    if (
        rule is None
        and key[0] == MICROSOFT_VENDOR_ID
        and (controller_type == "XBoxOneController")
    ):
        # Microsoft ships Bluetooth and Windows-driver identities under this type;
        # a new one must be reviewed before it can bind the USB-only GIP driver.
        raise CatalogError(f"unreviewed Microsoft SDL XBoxOneController row {key}")
    return rule


def build_sdl_records(
    rows: list[tuple[int, int, str]],
    existing: dict[tuple[int, int], str],
) -> tuple[dict[tuple[int, int], dict[str, Any]], dict[str, int]]:
    """Admits SDL identities absent from `existing` (identity -> family).

    Every distinct identity lands in exactly one count bucket, independent of row order.
    """
    types: dict[tuple[int, int], set[str]] = {}
    for vendor_id, product_id, controller_type in rows:
        types.setdefault((vendor_id, product_id), set()).add(controller_type)

    for key, (expected_type, _) in sorted(SDL_EXCLUSIONS.items()):
        if expected_type not in types.get(key, set()):
            raise CatalogError(
                f"stale SDL exclusion {key}: not listed as {expected_type}"
            )

    records: dict[tuple[int, int], dict[str, Any]] = {}
    counts: dict[str, int] = {}

    def count(bucket: str) -> None:
        counts[bucket] = counts.get(bucket, 0) + 1

    for key in sorted(types):
        if len(types[key]) > 1:
            count("sdl-conflict")
            continue
        (controller_type,) = types[key]
        mapping = SDL_FAMILIES.get(controller_type)
        if mapping is None:
            count(f"unmapped:{controller_type}")
            continue
        family, variant = mapping
        if key in existing:
            if key in SDL_EXCLUSIONS:
                raise CatalogError(f"redundant SDL exclusion {key}: already catalogued")
            count("duplicate" if existing[key] == family else "conflict")
            continue
        reason = sdl_skip_reason(key, controller_type)
        if reason is not None:
            count(f"excluded:{reason}")
            continue
        if family == "valve.steam-controller":
            if key not in STEAM_VARIANTS:
                raise CatalogError(f"Steam row {key} has no STEAM_VARIANTS entry")
            variant = STEAM_VARIANTS[key]
        protocol: dict[str, Any] = {"family": family}
        if variant is not None:
            protocol["variant"] = variant
        quirks = (["switch-2"] if key in SWITCH_2_IDENTITIES else []) + SDL_QUIRKS.get(
            controller_type, []
        )
        if quirks:
            protocol["quirks"] = quirks
        vendor_id, product_id = key
        records[key] = {
            "$schema": RECORD_SCHEMA_ID,
            "vendorID": vendor_id,
            "productID": product_id,
            "protocol": protocol,
        }
        count("added")
    return records, counts


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
    return int(record["vendorID"]), int(record["productID"])


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
        sdl = lock["sdl"]
        if sdl["repository"] != "libsdl-org/SDL":
            raise CatalogError("unsupported SDL repository")
        if len(sdl["commit"]) != 40:
            raise CatalogError("SDL commit must be a full SHA")
        if len(sdl["files"]["controller_list"]["sha256"]) != 64:
            raise CatalogError("SDL controller_list SHA-256 is invalid")
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
            else {"$schema", "operation", "vendorID", "productID", "set"}
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
            key = (int(document["vendorID"]), int(document["productID"]))
            payload = document["set"]
            if not payload or not set(payload) <= {"protocol", "usb"}:
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
                raise CatalogError(
                    f"add override conflicts with upstream identity {key}"
                )
            records[key] = payload
            continue
        if upstream is None:
            raise CatalogError(f"orphan patch override for {key}")
        merged = {**upstream, **payload}
        if merged == upstream:
            raise CatalogError(f"redundant patch override for {key}")
        records[key] = merged


def merge_sdl_records(
    records: dict[tuple[int, int], dict[str, Any]],
    overrides: list[tuple[str, tuple[int, int], dict[str, Any]]],
    rows: list[tuple[int, int, str]],
) -> dict[str, int]:
    """Adds SDL identities to Linux `records`; Linux rows and add overrides win."""
    existing = {key: record["protocol"]["family"] for key, record in records.items()}
    for operation, key, payload in overrides:
        if operation == "add":
            existing[key] = payload["protocol"]["family"]
    sdl_records, counts = build_sdl_records(rows, existing)
    records.update(sdl_records)
    return counts


def build_catalog() -> dict[tuple[int, int], dict[str, Any]]:
    generator = load_module(
        "ojd_generate_xpad_records",
        ROOT / "Scripts" / "Catalog" / "generate_xpad_records.py",
    )
    validator = load_module(
        "ojd_validate_profiles",
        ROOT / "Scripts" / "Catalog" / "validate_profiles.py",
    )
    lock = load_lock()
    linux = lock["linux"]

    sources = load_locked_files(linux)
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

    overrides = load_overrides(validator)
    sdl_rows = parse_sdl_controllers(load_locked_files(lock["sdl"])["controller_list"])
    sdl_counts = merge_sdl_records(records, overrides, sdl_rows)
    apply_overrides(records, overrides)

    if not records:
        raise CatalogError("generation produced no controller records")

    with tempfile.TemporaryDirectory() as directory:
        temporary_root = pathlib.Path(directory)
        for key, record in sorted(records.items()):
            path = record_path(temporary_root, key)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json_text(record))
            validator.validate_record(path, enforce_path=False)

    if skipped:
        print(f"Linux rows intentionally skipped: {len(skipped)}")
    print(sdl_summary(sdl_rows, sdl_counts))
    return records


def sdl_summary(rows: list[tuple[int, int, str]], counts: dict[str, int]) -> str:
    unmapped = sum(
        value
        for bucket, value in counts.items()
        if bucket.startswith("unmapped:") or bucket == "sdl-conflict"
    )
    identities = sum(counts.values())
    lines = [
        (
            f"SDL rows parsed: {len(rows)} ({identities} identities); "
            f"mapped {identities - unmapped}, added {counts.get('added', 0)}, "
            f"duplicates {counts.get('duplicate', 0)}, "
            f"conflicts {counts.get('conflict', 0)}"
        ),
        *(
            f"  skipped {bucket}: {value}"
            for bucket, value in sorted(counts.items())
            if bucket not in {"added", "duplicate", "conflict"}
        ),
    ]
    return "\n".join(lines)


def expected_files(
    records: dict[tuple[int, int], dict[str, Any]],
) -> dict[pathlib.Path, str]:
    return {
        record_path(OUTPUT_DIR, key): json.dumps(record, indent=2, ensure_ascii=False)
        + "\n"
        for key, record in sorted(records.items())
    }


def check_catalog(records: dict[tuple[int, int], dict[str, Any]]) -> None:
    expected = expected_files(records)
    actual = set(OUTPUT_DIR.glob("*/*.json"))
    missing = sorted(set(expected) - actual)
    stale = sorted(actual - set(expected))
    changed = sorted(
        path
        for path, text in expected.items()
        if path.exists() and path.read_text() != text
    )
    if missing or stale or changed:
        details = [
            *(f"missing {path.relative_to(ROOT)}" for path in missing),
            *(f"stale {path.relative_to(ROOT)}" for path in stale),
            *(f"changed {path.relative_to(ROOT)}" for path in changed),
        ]
        raise CatalogError(
            "catalog differs from generated output:\n" + "\n".join(details)
        )


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
