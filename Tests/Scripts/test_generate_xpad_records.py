from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


generator = load_module(
    "ojd_generate_xpad_records",
    ROOT / "scripts" / "catalog" / "generate-xpad-records.py",
)
validator = load_module(
    "ojd_validate_profiles",
    ROOT / "scripts" / "catalog" / "validate-profiles.py",
)


SOURCE = r"""
#define MAP_DPAD_TO_BUTTONS BIT(0)
#define MAP_TRIGGERS_TO_BUTTONS BIT(1)
#define MAP_STICKS_TO_NULL BIT(2)
#define MAP_SHARE_BUTTON BIT(3)
#define MAP_PADDLES BIT(4)
#define MAP_PROFILE_BUTTON BIT(5)
#define MAP_SHARE_OFFSET BIT(6)
#define DANCEPAD_MAP_CONFIG (MAP_DPAD_TO_BUTTONS | MAP_TRIGGERS_TO_BUTTONS | MAP_STICKS_TO_NULL)
#define FLAG_DELAY_INIT BIT(0)

static const struct xpad_device {
    int idVendor;
    int idProduct;
    char *name;
    int mapping;
    int xtype;
    int flags;
} xpad_device[] = {
    { 0x1111, 0x0001, "Example Dance Pad", DANCEPAD_MAP_CONFIG, XTYPE_XBOX360 },
    { 0x2222, 0x0002, "Example Elite Pad", MAP_SHARE_BUTTON | MAP_PADDLES, XTYPE_XBOXONE },
    { 0x045e, 0x02ea, "Example Xbox One S", 0, XTYPE_XBOXONE },
    { 0x045e, 0x0719, "Example Wireless Receiver", MAP_DPAD_TO_BUTTONS, XTYPE_XBOX360W },
    { 0x366c, 0x0005, "Example Delayed Pad", MAP_SHARE_BUTTON, XTYPE_XBOXONE, FLAG_DELAY_INIT },
    { 0x0000, 0x0000, "Generic X-Box pad", 0, XTYPE_UNKNOWN }
};

static const struct xboxone_init_packet xboxone_init_packets[] = {
    XBOXONE_INIT_PKT(0x0000, 0x0000, xboxone_power_on),
    XBOXONE_INIT_PKT(0x045e, 0x02ea, xboxone_s_init),
    XBOXONE_INIT_PKT(0x0000, 0x0000, xboxone_led_on),
    XBOXONE_INIT_PKT(0x0000, 0x0000, xboxone_auth_done),
};
"""


class XpadRecordGeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.devices = generator.parse_devices(SOURCE)
        self.init_rules = generator.parse_init_rules(SOURCE)

    def test_parses_device_table_and_init_rules(self) -> None:
        self.assertEqual(len(self.devices), 5)
        self.assertEqual(len(self.init_rules), 4)
        self.assertEqual(self.devices[0].name, "Example Dance Pad")
        self.assertEqual(
            generator.parse_mapping_flags(self.devices[0].mapping_expression),
            ["dpadToButtons", "triggersToButtons", "sticksToNull"],
        )

    def test_builds_schema_valid_wired_profiles(self) -> None:
        candidates, skipped, filtered_out = generator.generate_candidates(
            devices=self.devices,
            init_rules=self.init_rules,
            existing_keys=set(),
            include_existing=False,
            requested_type="all",
            vendor_id=None,
            product_id=None,
        )

        self.assertEqual(filtered_out, 0)
        self.assertEqual(len(candidates), 4)
        self.assertEqual(
            {item["reason"] for item in skipped},
            {
                "unsupported_device_flags:FLAG_DELAY_INIT",
            },
        )

        by_key = {
            (item.device.vendor_id, item.device.product_id): item for item in candidates
        }
        xbox360 = by_key[(0x1111, 0x0001)].profile
        self.assertNotIn("usb", xbox360)
        self.assertNotIn("name", xbox360)
        self.assertEqual(xbox360["protocol"]["driver"], "Xbox360")

        wireless = by_key[(0x045E, 0x0719)].profile
        self.assertEqual(wireless["protocol"]["driver"], "Xbox360")
        self.assertEqual(wireless["protocol"]["variant"], "xbox360Wireless")
        self.assertEqual(
            wireless["protocol"]["flags"],
            ["dpadToButtons"],
        )

        elite = by_key[(0x2222, 0x0002)].profile
        self.assertEqual(elite["protocol"]["flags"], ["shareButton", "paddles"])
        self.assertNotIn("startup_packets", elite["protocol"])

        xbox_one_s = by_key[(0x045E, 0x02EA)].profile
        self.assertEqual(
            xbox_one_s["protocol"]["startup_packets"],
            ["powerOn", "xboxOneSInit", "ledOn", "authDone"],
        )

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for item in candidates:
                path = root / item.filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(generator.json_text(item.profile))
                _, _, _, hardware_verified = validator.validate_record(path, enforce_path=False)
                self.assertFalse(hardware_verified)

    def test_skips_existing_profiles_by_default(self) -> None:
        candidates, skipped, _ = generator.generate_candidates(
            devices=self.devices,
            init_rules=self.init_rules,
            existing_keys={(0x2222, 0x0002)},
            include_existing=False,
            requested_type="xboxOne",
            vendor_id=None,
            product_id=None,
        )

        self.assertNotIn(
            (0x2222, 0x0002),
            {(item.device.vendor_id, item.device.product_id) for item in candidates},
        )
        self.assertIn("already_bundled", {item["reason"] for item in skipped})

    def test_writer_is_idempotent_and_refuses_silent_overwrite(self) -> None:
        candidates, skipped, filtered_out = generator.generate_candidates(
            devices=self.devices,
            init_rules=self.init_rules,
            existing_keys=set(),
            include_existing=False,
            requested_type="xbox360",
            vendor_id=0x1111,
            product_id=0x0001,
        )
        manifest = {
            "counts": {
                "profiles": len(candidates),
                "skipped": len(skipped),
                "filtered_out": filtered_out,
            }
        }

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            generator.write_catalog(root, candidates, manifest, force=False)
            generator.write_catalog(root, candidates, manifest, force=False)
            profile_path = root / candidates[0].filename
            profile_path.write_text(json.dumps({"changed": True}) + "\n")
            with self.assertRaises(generator.GenerationError):
                generator.write_catalog(root, candidates, manifest, force=False)

    def test_partial_device_table_parse_is_rejected(self) -> None:
        malformed = SOURCE.replace("XTYPE_XBOXONE },", "XTYPE-XBOXONE },", 1)
        with self.assertRaises(generator.GenerationError):
            generator.parse_devices(malformed)

    def test_unknown_mapping_macro_is_rejected(self) -> None:
        with self.assertRaises(generator.GenerationError):
            generator.parse_mapping_flags("MAP_SHARE_BUTTON | MAP_FUTURE_BUTTON")


if __name__ == "__main__":
    unittest.main()
