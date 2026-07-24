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


catalog = load_module(
    "ojd_generate_controller_catalog",
    ROOT / "scripts" / "catalog" / "generate-controller-catalog.py",
)
validator = load_module(
    "ojd_validate_canonical_profiles",
    ROOT / "scripts" / "catalog" / "validate-profiles.py",
)

SCHEMA_ID = validator.SCHEMA_ID
OVERRIDE_SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller-override.schema.json"
)


def record(vendor_id: int = 1, product_id: int = 2):
    return {
        "$schema": SCHEMA_ID,
        "vendor_id": vendor_id,
        "product_id": product_id,
        "transport": "usb",
        "protocol": {"driver": "GIP", "variant": "xboxOne"},
        "provenance": {"source": "linux-xpad.c", "verified": False},
    }


class CanonicalRecordValidationTests(unittest.TestCase):
    def validate_document(self, document):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "record.json"
            path.write_text(json.dumps(document))
            return validator.validate_record(path, enforce_path=False)

    def test_unknown_field_is_rejected(self):
        document = record()
        document["name"] = "custom display name"
        with self.assertRaisesRegex(validator.ValidationError, "unknown fields"):
            self.validate_document(document)

    def test_redundant_protocol_endpoints_are_rejected(self):
        document = record()
        document["usb"] = {"endpoints": {"in": 130, "out": 2}}
        with self.assertRaisesRegex(validator.ValidationError, "must be omitted"):
            self.validate_document(document)

    def test_gip_keep_alive_policy_is_validated(self):
        document = record()
        document["protocol"]["keep_alive"] = False
        self.validate_document(document)

        document["protocol"]["keep_alive"] = True
        self.validate_document(document)

        document["protocol"]["keep_alive"] = "unsupported"
        with self.assertRaisesRegex(validator.ValidationError, "keep_alive"):
            self.validate_document(document)

        document = record()
        document["protocol"] = {
            "driver": "Xbox360",
            "variant": "xbox360",
            "keep_alive": False,
        }
        with self.assertRaisesRegex(validator.ValidationError, "requires GIP"):
            self.validate_document(document)

    def test_duplicate_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for parent, filename in [("0001", "one.json"), ("0002", "two.json")]:
                path = root / parent / filename
                path.parent.mkdir()
                path.write_text(json.dumps(record()))
            with self.assertRaisesRegex(validator.ValidationError, "duplicate identity"):
                validator.validate_catalog(root)


class HIDImporterTests(unittest.TestCase):
    def test_supported_hid_records_are_derived_from_locked_tables(self):
        definitions: dict[str, int] = {}
        sources = {
            "hid_ids": "",
            "hid_sony": "",
            "hid_playstation": "",
            "hid_nintendo": "",
            "hid_steam": "",
        }
        next_value = 1
        for source_key, vendor, product, *_ in catalog.HID_RECORDS:
            for macro in (vendor, product):
                if macro not in definitions:
                    definitions[macro] = next_value
                    next_value += 1
            sources[source_key] += f"HID_USB_DEVICE({vendor}, {product})\n"
        sources["hid_ids"] = "".join(
            f"#define {macro} 0x{value:04x}\n"
            for macro, value in definitions.items()
        )

        records = catalog.build_hid_records(sources)

        self.assertEqual(len(records), len(catalog.HID_RECORDS))
        self.assertTrue(all(record["transport"] == "hid" for record in records))
        self.assertTrue(all(record["provenance"]["verified"] is False for record in records))


class OverrideTests(unittest.TestCase):
    def test_unknown_override_field_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            path = root / "0001" / "0001-0002.json"
            path.parent.mkdir()
            path.write_text(json.dumps({
                "$schema": OVERRIDE_SCHEMA_ID,
                "operation": "patch",
                "vendor_id": 1,
                "product_id": 2,
                "set": {"provenance": {"source": "local-hardware", "verified": True}},
                "unknown": True,
            }))
            with self.assertRaisesRegex(catalog.CatalogError, "invalid override shape"):
                catalog.load_overrides(validator, root)

    def test_add_conflict_is_rejected(self):
        base = record()
        records = {(1, 2): base}
        with self.assertRaisesRegex(catalog.CatalogError, "conflicts"):
            catalog.apply_overrides(records, [("add", (1, 2), base)])

    def test_orphan_patch_is_rejected(self):
        with self.assertRaisesRegex(catalog.CatalogError, "orphan"):
            catalog.apply_overrides(
                {},
                [(
                    "patch",
                    (1, 2),
                    {"provenance": {"source": "local-hardware", "verified": True}},
                )],
            )

    def test_redundant_patch_is_rejected(self):
        base = record()
        records = {(1, 2): base}
        with self.assertRaisesRegex(catalog.CatalogError, "redundant"):
            catalog.apply_overrides(
                records,
                [("patch", (1, 2), {"protocol": base["protocol"]})],
            )

    def test_explicit_local_patch_replaces_only_selected_sections(self):
        base = record()
        records = {(1, 2): base}
        catalog.apply_overrides(
            records,
            [(
                "patch",
                (1, 2),
                {
                    "protocol": {
                        "driver": "GIP",
                        "variant": "xboxOne",
                        "flags": ["shareButton"],
                    },
                    "provenance": {
                        "source": "local-hardware",
                        "verified": True,
                    },
                },
            )],
        )
        self.assertEqual(records[(1, 2)]["vendor_id"], 1)
        self.assertEqual(records[(1, 2)]["protocol"]["flags"], ["shareButton"])
        self.assertTrue(records[(1, 2)]["provenance"]["verified"])


if __name__ == "__main__":
    unittest.main()
