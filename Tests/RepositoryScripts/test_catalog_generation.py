from __future__ import annotations

import base64
import hashlib
import json
import unittest
import urllib.error
from email.message import Message
from typing import Any, ClassVar
from unittest.mock import patch

from Scripts.Catalog import generate_controller_catalog as catalog
from Scripts.Catalog import generate_xpad_records as xpad


def hid_source(vendor: str, product: str) -> str:
    return f"static const struct hid_device_id ids[] = {{ HID_USB_DEVICE({vendor}, {product}) }};"


class CatalogGenerationTests(unittest.TestCase):
    def test_rate_limited_download_uses_authenticated_github_fallback(self) -> None:
        source = "static const int xpad_device[] = {0};\n"
        linux = {
            "repository": "torvalds/linux",
            "commit": "a" * 40,
            "files": {
                "xpad": {
                    "path": "drivers/input/joystick/xpad.c",
                    "sha256": hashlib.sha256(source.encode()).hexdigest(),
                }
            },
        }
        rate_limit = urllib.error.HTTPError(
            "https://raw.githubusercontent.com",
            429,
            "Too Many Requests",
            Message(),
            None,
        )
        response = json.dumps({"content": base64.b64encode(source.encode()).decode()})

        with (
            patch.object(catalog.urllib.request, "urlopen", side_effect=rate_limit),
            patch.object(catalog, "run_gh", return_value=response) as run_gh,
        ):
            files = catalog.load_locked_files(linux)

        self.assertEqual(files, {"xpad": source})
        run_gh.assert_called_once_with(
            [
                "api",
                "-X",
                "GET",
                "repos/torvalds/linux/contents/drivers/input/joystick/xpad.c",
                "-f",
                f"ref={'a' * 40}",
            ],
            catalog.CatalogError,
        )


class XpadTranslationTests(unittest.TestCase):
    def device(self, xtype: str, mapping: str) -> xpad.XpadDevice:
        return xpad.XpadDevice(
            vendor_id=0x0C12,
            product_id=0x8809,
            name="pad",
            mapping_expression=mapping,
            xtype=xtype,
            flags_expression="0",
        )

    def test_dance_pad_mapping_becomes_capability_absences(self) -> None:
        profile = xpad.build_profile(
            self.device("XTYPE_XBOX", "DANCEPAD_MAP_CONFIG"), init_rules=[]
        )
        self.assertEqual(
            profile["protocol"], {"family": "xbox.xid", "variant": "gamepad"}
        )
        self.assertNotIn("transport", profile)
        self.assertEqual(
            profile["capabilities"],
            {
                "absent": [
                    "left-stick-x",
                    "left-stick-y",
                    "right-stick-x",
                    "right-stick-y",
                    "left-trigger",
                    "right-trigger",
                ]
            },
        )

    def test_delayed_init_is_accepted_only_where_the_driver_performs_it(self) -> None:
        def device(xtype: str) -> xpad.XpadDevice:
            return xpad.XpadDevice(
                vendor_id=0x366C,
                product_id=0x0005,
                name="pad",
                mapping_expression="0",
                xtype=xtype,
                flags_expression="FLAG_DELAY_INIT",
            )

        candidates, skipped, _ = xpad.generate_candidates(
            devices=[device("XTYPE_XBOXONE")],
            init_rules=[xpad.InitRule(0, 0, "xboxone_power_on")],
            existing_keys=set(),
            include_existing=True,
            requested_type="all",
            vendor_id=None,
            product_id=None,
        )
        self.assertEqual(skipped, [])
        self.assertEqual(
            candidates[0].profile["protocol"],
            {
                "family": "xbox.gip",
                "initialization": ["xbox.gip/power-on"],
            },
        )
        _, skipped, _ = xpad.generate_candidates(
            devices=[device("XTYPE_XBOX360")],
            init_rules=[xpad.InitRule(0, 0, "xboxone_power_on")],
            existing_keys=set(),
            include_existing=True,
            requested_type="all",
            vendor_id=None,
            product_id=None,
        )
        self.assertEqual(
            skipped[0]["reason"], "unsupported_device_flags:FLAG_DELAY_INIT"
        )

    def test_gip_share_offset_and_initialization_use_driver_ids(self) -> None:
        rules = [
            xpad.InitRule(0, 0, "xboxone_power_on"),
            xpad.InitRule(0x0C12, 0x8809, "xboxone_s_init"),
            xpad.InitRule(0, 0, "xboxone_led_on"),
            xpad.InitRule(0, 0, "xboxone_auth_done"),
        ]
        profile = xpad.build_profile(
            self.device("XTYPE_XBOXONE", "MAP_SHARE_BUTTON | MAP_SHARE_OFFSET"), rules
        )
        self.assertEqual(
            profile["protocol"],
            {
                "family": "xbox.gip",
                "quirks": ["share-offset"],
                "initialization": [
                    "xbox.gip/power-on",
                    "xbox.gip/s-init",
                    "xbox.gip/led-on",
                    "xbox.gip/auth-done",
                ],
            },
        )
        self.assertNotIn("capabilities", profile)

    def test_quirk_outside_its_driver_is_rejected(self) -> None:
        with self.assertRaises(xpad.GenerationError):
            xpad.build_profile(
                self.device("XTYPE_XBOX360", "MAP_SHARE_OFFSET"), init_rules=[]
            )

    def test_xpad_types_map_to_family_and_stored_variant(self) -> None:
        expected = {
            "XTYPE_XBOX": {"family": "xbox.xid", "variant": "gamepad"},
            "XTYPE_XBOX360": {"family": "xbox.xusb", "variant": "wired"},
            "XTYPE_XBOX360W": {"family": "xbox.xusb", "variant": "receiver"},
        }
        for xtype, protocol in expected.items():
            with self.subTest(xtype):
                profile = xpad.build_profile(self.device(xtype, "0"), init_rules=[])
                self.assertEqual(profile["protocol"], protocol)


class HIDRecordTests(unittest.TestCase):
    def test_steam_receiver_is_the_dongle_variant_without_quirks(self) -> None:
        defines = (
            "#define USB_VENDOR_ID_VALVE 0x28de\n"
            "#define USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS 0x1142\n"
        )
        entries = [
            row
            for row in catalog.HID_RECORDS
            if row[2] == "USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS"
        ]
        with patch.object(catalog, "HID_RECORDS", tuple(entries)):
            records = catalog.build_hid_records(
                {
                    "hid_ids": defines,
                    "hid_steam": hid_source(
                        "USB_VENDOR_ID_VALVE", "USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS"
                    ),
                }
            )
        self.assertEqual(
            records[0]["protocol"],
            {"family": "valve.steam-controller", "variant": "dongle"},
        )
        self.assertNotIn("transport", records[0])

    def test_patch_override_rejects_the_removed_transport_field(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "045e" / "045e-02ea.json"
            path.parent.mkdir()
            path.write_text(
                json.dumps(
                    {
                        "$schema": (
                            "https://raw.githubusercontent.com/xsyetopz/"
                            "OpenJoystickDriver/main/Resources/Schemas/v1beta1/"
                            "controller-override.schema.json"
                        ),
                        "operation": "patch",
                        "vendorID": 0x045E,
                        "productID": 0x02EA,
                        "set": {"transport": "hid"},
                    }
                )
            )
            with self.assertRaises(catalog.CatalogError):
                catalog.load_overrides(validator=None, override_dir=root)

    def test_patch_override_adds_tuning(self) -> None:
        import tempfile
        from pathlib import Path

        tuning = {"stickDeadzone": 0.02}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "11c1" / "11c1-5600.json"
            path.parent.mkdir()
            path.write_text(
                json.dumps(
                    {
                        "$schema": (
                            "https://raw.githubusercontent.com/xsyetopz/"
                            "OpenJoystickDriver/main/Resources/Schemas/v1beta1/"
                            "controller-override.schema.json"
                        ),
                        "operation": "patch",
                        "vendorID": 0x11C1,
                        "productID": 0x5600,
                        "set": {"tuning": tuning},
                    }
                )
            )
            overrides = catalog.load_overrides(validator=None, override_dir=root)
        upstream = {"protocol": {"family": "hid.descriptor"}}
        records = {(0x11C1, 0x5600): upstream}
        catalog.apply_overrides(records, overrides)
        self.assertEqual(records[(0x11C1, 0x5600)], {**upstream, "tuning": tuning})


SDL_FIXTURE = """\
#define MAKE_CONTROLLER_ID( nVID, nPID )\t(unsigned int)( (unsigned int)nVID << 16 | (unsigned int)nPID )

static const ControllerDescription_t arrControllers[] = {
\t{ MAKE_CONTROLLER_ID( 0x054c, 0x0268 ), k_eControllerType_PS3Controller, NULL },\t// Sony PS3 Controller
\t//{ MAKE_CONTROLLER_ID( 0x046d, 0xc24f ), k_eControllerType_PS3Controller, NULL },\t// Logitech G29 (PS3)
\t{ MAKE_CONTROLLER_ID( 0x1532, 0X0401 ), k_eControllerType_PS4Controller, NULL },\t// Razer Panthera
    { MAKE_CONTROLLER_ID (0x9886, 0x0024 ), k_eControllerType_XInputPS4Controller, NULL },  // Astro C40
\t{ MAKE_CONTROLLER_ID( 0x2f24,\t0x2e ), k_eControllerType_XBoxOneController, NULL },\t// Unknown Controller
\t{ MAKE_CONTROLLER_ID( 0x0,\t\t0x6686 ), k_eControllerType_XBoxOneController, NULL },\t// Unknown Controller
\t// Added 12-17-2020
\t{ MAKE_CONTROLLER_ID( 0x0e6f, 0x018c ), k_eControllerType_SwitchProController, "PDP REALMz Wireless Controller" },  // PDP
};
"""


class SDLControllerListTests(unittest.TestCase):
    def test_parser_reads_active_rows_in_every_spelling(self) -> None:
        self.assertEqual(
            catalog.parse_sdl_controllers(SDL_FIXTURE),
            [
                (0x054C, 0x0268, "PS3Controller"),
                (0x1532, 0x0401, "PS4Controller"),
                (0x9886, 0x0024, "XInputPS4Controller"),
                (0x2F24, 0x002E, "XBoxOneController"),
                (0x0000, 0x6686, "XBoxOneController"),
                (0x0E6F, 0x018C, "SwitchProController"),
            ],
        )

    def test_unparsed_row_inside_the_table_fails_generation(self) -> None:
        source = SDL_FIXTURE.replace(
            "};", "\t{ MAKE_CONTROLLER_ID( 0x0001, 0x0002 ), 7, NULL },\n};"
        )
        with self.assertRaises(catalog.CatalogError):
            catalog.parse_sdl_controllers(source)

    def build(
        self,
        rows: list[tuple[int, int, str]],
        existing: dict[tuple[int, int], str] | None = None,
    ) -> tuple[dict[tuple[int, int], dict[str, object]], dict[str, int]]:
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", {}),
        ):
            return catalog.build_sdl_records(rows, existing or {})

    def test_types_map_to_implemented_families_and_variants(self) -> None:
        expected = {
            "PS3Controller": {"family": "sony.sixaxis"},
            "PS4Controller": {"family": "sony.dualshock4"},
            "PS5Controller": {"family": "sony.dualsense"},
            "SwitchProController": {"family": "nintendo.switch1"},
            "XBox360Controller": {"family": "xbox.xusb", "variant": "wired"},
            "XBoxOneController": {"family": "xbox.gip"},
            "SwitchInputOnlyController": {
                "family": "nintendo.switch1",
                "quirks": ["input-only"],
            },
        }
        for controller_type, protocol in expected.items():
            with self.subTest(controller_type):
                records, counts = self.build([(0x054C, 0x1234, controller_type)])
                self.assertEqual(records[(0x054C, 0x1234)]["protocol"], protocol)
                self.assertEqual(counts, {"added": 1})

    def test_steam_rows_store_the_variant_their_sdl_row_names(self) -> None:
        rows = [
            (0x28DE, 0x1101, "SteamController"),
            (0x28DE, 0x1105, "SteamController"),
            (0x28DE, 0x1106, "SteamController"),
            (0x28DE, 0x1201, "SteamControllerV2"),
            (0x28DE, 0x1202, "SteamControllerV2"),
            (0x28DE, 0x1205, "SteamControllerNeptune"),
            (0x28DE, 0x1302, "SteamControllerTriton"),
            (0x28DE, 0x1303, "SteamControllerTriton"),
            (0x28DE, 0x1304, "SteamControllerTriton"),
            (0x28DE, 0x1305, "SteamControllerTriton"),
        ]
        records, counts = self.build(rows)
        protocols = {key[1]: record["protocol"] for key, record in records.items()}
        steam = "valve.steam-controller"
        wired = {"family": steam, "variant": "wired"}
        ble = {"family": steam, "variant": "bluetooth-le"}
        self.assertEqual(
            protocols,
            {
                0x1101: wired,
                0x1105: ble,
                0x1106: ble,
                0x1201: wired,
                0x1202: ble,
                0x1205: {**wired, "quirks": ["neptune"]},
                0x1302: {**wired, "quirks": ["triton"]},
                0x1303: {**ble, "quirks": ["triton"]},
                0x1304: {"family": steam, "variant": "dongle", "quirks": ["triton"]},
                0x1305: {"family": steam, "variant": "dongle", "quirks": ["triton"]},
            },
        )
        self.assertEqual(counts, {"added": 10})

    def test_switch_2_rows_carry_the_switch_2_quirk_before_the_side(self) -> None:
        rows = [
            (0x057E, 0x2006, "SwitchJoyConLeft"),
            (0x057E, 0x2066, "SwitchJoyConRight"),
            (0x057E, 0x2067, "SwitchJoyConLeft"),
            (0x057E, 0x2069, "SwitchProController"),
        ]
        records, counts = self.build(rows)
        protocols = {key[1]: record["protocol"] for key, record in records.items()}
        switch = "nintendo.switch1"
        self.assertEqual(
            protocols,
            {
                0x2006: {"family": switch, "quirks": ["joy-con-left"]},
                0x2066: {"family": switch, "quirks": ["switch-2", "joy-con-right"]},
                0x2067: {"family": switch, "quirks": ["switch-2", "joy-con-left"]},
                0x2069: {"family": switch, "quirks": ["switch-2"]},
            },
        )
        self.assertEqual(counts, {"added": 4})

    def test_a_steam_row_without_a_known_variant_fails_generation(self) -> None:
        with self.assertRaises(catalog.CatalogError):
            self.build([(0x28DE, 0x11FE, "SteamController")])

    def test_unmapped_and_excluded_types_are_skipped_and_counted(self) -> None:
        rows = [
            (0x057E, 0x2008, "SwitchJoyConPair"),
            (0x0079, 0x0006, "UnknownNonSteamController"),
            (0x0000, 0x6686, "XBoxOneController"),
        ]
        records, counts = self.build(rows)
        self.assertEqual(records, {})
        self.assertEqual(
            counts,
            {
                "unmapped:SwitchJoyConPair": 1,
                "unmapped:UnknownNonSteamController": 1,
                "excluded:not-usb-identity": 1,
            },
        )

    def test_an_unreviewed_nvidia_row_fails_generation(self) -> None:
        with self.assertRaises(catalog.CatalogError):
            self.build([(0x0955, 0x7210, "XBox360Controller")])

    def test_the_shield_controller_binds_the_shield_driver(self) -> None:
        shield = {(0x0955, 0x7210): catalog.SDL_IDENTITY_FAMILIES[(0x0955, 0x7210)]}
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", shield),
        ):
            records, counts = catalog.build_sdl_records(
                [(0x0955, 0x7210, "XBox360Controller")], {}
            )
        self.assertEqual(
            records[(0x0955, 0x7210)]["protocol"], {"family": "vendor.nvidia-shield"}
        )
        self.assertEqual(counts, {"added": 1})

    def test_xinput_mode_rows_are_bound_by_interface_signature(self) -> None:
        rows = [
            (0x0F0D, 0x00ED, "XInputPS4Controller"),
            (0x0F0D, 0x00DC, "XInputSwitchController"),
        ]
        records, counts = self.build(rows)
        self.assertEqual(records, {})
        self.assertEqual(counts, {"interface-signature": 2})
        summary = catalog.sdl_summary(rows, counts)
        self.assertIn("mapped 2", summary)
        self.assertIn("bound by interface signature 2", summary)
        self.assertNotIn("skipped", summary)

    def test_existing_rows_win_as_duplicates_or_conflicts(self) -> None:
        existing = {
            (0x045E, 0x028E): "xbox.xusb",
            (0x28DE, 0x1102): "valve.steam-controller",
            (0x0E6F, 0x0147): "xbox.gip",
        }
        records, counts = self.build(
            [
                (0x045E, 0x028E, "XBox360Controller"),
                (0x28DE, 0x1102, "SteamController"),
                (0x0E6F, 0x0147, "XBox360Controller"),
            ],
            existing,
        )
        self.assertEqual(records, {})
        self.assertEqual(counts, {"duplicate": 2, "conflict": 1})

    def test_repeated_identity_counts_once_and_mixed_types_are_skipped(self) -> None:
        rows = [
            (0x146B, 0x0D10, "PS4Controller"),
            (0x0F0D, 0x00ED, "XInputPS4Controller"),
            (0x146B, 0x0D10, "PS4Controller"),
            (0x0F0D, 0x00ED, "XBoxOneController"),
            (0x0E6F, 0x018C, "SwitchProController"),
            (0x0E6F, 0x018C, "PS4Controller"),
        ]
        records, counts = self.build(rows)
        self.assertEqual(list(records), [(0x146B, 0x0D10)])
        self.assertEqual(
            counts, {"added": 1, "interface-signature": 1, "sdl-conflict": 1}
        )
        self.assertEqual(self.build(list(reversed(rows))), (records, counts))

    def test_exclusions_must_match_the_pinned_list_and_stay_uncatalogued(self) -> None:
        exclusions = {(0x057E, 0x2069): ("SwitchProController", "switch-2")}
        rows = [(0x057E, 0x2069, "SwitchProController")]
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", exclusions),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", {}),
        ):
            self.assertEqual(
                catalog.build_sdl_records(rows, {}), ({}, {"excluded:switch-2": 1})
            )
            with self.assertRaises(catalog.CatalogError):
                catalog.build_sdl_records([(0x057E, 0x2069, "PS5Controller")], {})
            with self.assertRaises(catalog.CatalogError):
                catalog.build_sdl_records(rows, {(0x057E, 0x2069): "nintendo.switch1"})

    def test_add_override_wins_over_an_sdl_identity(self) -> None:
        override = {
            "$schema": catalog.RECORD_SCHEMA_ID,
            "vendorID": 0x1532,
            "productID": 0x1000,
            "protocol": {"family": "hid.descriptor"},
        }
        overrides = [("add", (0x1532, 0x1000), override)]
        records: dict[tuple[int, int], dict[str, object]] = {}
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", {}),
        ):
            counts = catalog.merge_sdl_records(
                records, overrides, [(0x1532, 0x1000, "PS4Controller")]
            )
        self.assertEqual(counts, {"conflict": 1})
        catalog.apply_overrides(records, overrides)
        self.assertEqual(records, {(0x1532, 0x1000): override})

    def test_protocol_patch_merges_only_within_its_family(self) -> None:
        upstream = {
            "protocol": {"family": "xbox.gip", "quirks": ["share-offset"]},
            "usb": {"interface": 0},
        }
        records = {(1, 1): upstream, (1, 2): upstream, (1, 3): upstream}
        catalog.apply_overrides(
            records,
            [
                (
                    "patch",
                    (1, 1),
                    {"protocol": {"family": "xbox.gip", "keepAlive": False}},
                ),
                (
                    "patch",
                    (1, 2),
                    {"protocol": {"family": "xbox.gip", "quirks": ["x"]}},
                ),
                ("patch", (1, 3), {"protocol": {"family": "hid.descriptor"}}),
            ],
        )
        self.assertEqual(
            records[(1, 1)]["protocol"],
            {"family": "xbox.gip", "quirks": ["share-offset"], "keepAlive": False},
        )
        self.assertEqual(records[(1, 2)]["protocol"]["quirks"], ["x"])
        self.assertEqual(records[(1, 3)]["protocol"], {"family": "hid.descriptor"})
        self.assertEqual(records[(1, 3)]["usb"], {"interface": 0})

    def test_third_party_dualsense_is_admitted_and_360_product_ids_are_skipped(
        self,
    ) -> None:
        rows = [
            (0x1532, 0x100B, "PS5Controller"),
            (0x054C, 0x0CE6, "PS5Controller"),
            (0x1430, 0x0719, "XBoxOneController"),
            (0x1BAD, 0x028E, "XBoxOneController"),
            (0x1532, 0x0A15, "XBoxOneController"),
        ]
        records, counts = self.build(rows)
        self.assertEqual(
            sorted(records), [(0x054C, 0x0CE6), (0x1532, 0x0A15), (0x1532, 0x100B)]
        )
        self.assertEqual(
            records[(0x1532, 0x100B)]["protocol"],
            {"family": "sony.dualsense", "quirks": ["third-party"]},
        )
        self.assertEqual(
            records[(0x054C, 0x0CE6)]["protocol"], {"family": "sony.dualsense"}
        )
        self.assertEqual(counts, {"added": 3, "interface-signature": 2})

    def test_third_party_ps3_rows_bind_the_third_party_family(self) -> None:
        records, counts = self.build(
            [(0x0738, 0x3250, "PS3Controller"), (0x054C, 0x0268, "PS3Controller")]
        )
        self.assertEqual(
            records[(0x0738, 0x3250)]["protocol"], {"family": "vendor.ps3-third-party"}
        )
        self.assertEqual(
            records[(0x054C, 0x0268)]["protocol"], {"family": "sony.sixaxis"}
        )
        self.assertEqual(counts, {"added": 2})

    def test_identity_families_override_the_type_and_must_stay_listed(self) -> None:
        overrides = {
            (0x2563, 0x0523): ("PS3Controller", "sony.sixaxis", None),
            (0x0F0D, 0x0086): ("PS3Controller", "xbox.xusb", "wired"),
        }
        rows = [(0x2563, 0x0523, "PS3Controller"), (0x0F0D, 0x0086, "PS3Controller")]
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", overrides),
        ):
            records, counts = catalog.build_sdl_records(rows, {})
            with self.assertRaises(catalog.CatalogError):
                catalog.build_sdl_records(rows[:1], {})
        self.assertEqual(
            records[(0x2563, 0x0523)]["protocol"], {"family": "sony.sixaxis"}
        )
        self.assertEqual(
            records[(0x0F0D, 0x0086)]["protocol"],
            {"family": "xbox.xusb", "variant": "wired"},
        )
        self.assertEqual(counts, {"added": 2})

    def test_unreviewed_microsoft_xbox_one_row_fails_generation(self) -> None:
        with self.assertRaises(catalog.CatalogError):
            self.build([(0x045E, 0x0B99, "XBoxOneController")])
        records, counts = self.build(
            [(0x045E, 0x0B12, "XBoxOneController")], {(0x045E, 0x0B12): "xbox.gip"}
        )
        self.assertEqual((records, counts), ({}, {"duplicate": 1}))

    def test_exclusion_shadowed_by_a_rule_fails_generation(self) -> None:
        exclusions = {(0x0000, 0x0001): ("PS4Controller", "not-usb-identity")}
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", exclusions),
            self.assertRaises(catalog.CatalogError),
        ):
            catalog.build_sdl_records([(0x0000, 0x0001, "PS4Controller")], {})

    def test_backbone_one_ps5_v2_uses_the_descriptor_mapping(self) -> None:
        backbone = (0x358A, 0x0304)
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(
                catalog,
                "SDL_IDENTITY_FAMILIES",
                {backbone: catalog.SDL_IDENTITY_FAMILIES[backbone]},
            ),
        ):
            records, _ = catalog.build_sdl_records([(*backbone, "PS5Controller")], {})
        self.assertEqual(
            records[(0x358A, 0x0304)]["protocol"], {"family": "hid.descriptor"}
        )

    def test_records_carry_no_provenance(self) -> None:
        records, _ = self.build([(0x1532, 0x1000, "PS4Controller")])
        self.assertEqual(
            set(records[(0x1532, 0x1000)]),
            {"$schema", "vendorID", "productID", "protocol"},
        )


def committed_records() -> dict[tuple[int, int], dict[str, Any]]:
    records: dict[tuple[int, int], dict[str, Any]] = {}
    for path in sorted(catalog.OUTPUT_DIR.glob("*/*.json")):
        record = json.loads(path.read_text())
        records[catalog.record_key(record)] = record
    return records


class CommittedCatalogTests(unittest.TestCase):
    """Data-level invariants of the generated catalog; no network needed."""

    def setUp(self) -> None:
        self.records = committed_records()

    def test_backbone_one_ps5_v2_is_not_catalogued_as_dualsense(self) -> None:
        record = self.records.get((0x358A, 0x0304))
        if record is not None:
            self.assertEqual(record["protocol"]["family"], "hid.descriptor")

    def test_excluded_sdl_identities_are_not_catalogued(self) -> None:
        self.assertEqual(sorted(set(catalog.SDL_EXCLUSIONS) & set(self.records)), [])


class PinnedSDLDataTests(unittest.TestCase):
    """Runs the real exclusion list against the pinned SDL list and committed catalog."""

    rows: ClassVar[list[tuple[int, int, str]]] = []

    @classmethod
    def setUpClass(cls) -> None:
        lock = json.loads(catalog.LOCK_PATH.read_text())
        try:
            source = catalog.load_locked_files(lock["sdl"])["controller_list"]
        except (OSError, catalog.CatalogError) as error:
            raise unittest.SkipTest(
                f"pinned SDL source unavailable: {error}"
            ) from error
        cls.rows = catalog.parse_sdl_controllers(source)

    def test_every_microsoft_xbox_one_row_is_catalogued_or_excluded(self) -> None:
        records = committed_records()
        unreviewed = sorted(
            (vendor_id, product_id)
            for vendor_id, product_id, controller_type in self.rows
            if vendor_id == 0x045E
            and controller_type == "XBoxOneController"
            and (vendor_id, product_id) not in records
            and (vendor_id, product_id) not in catalog.SDL_EXCLUSIONS
        )
        self.assertEqual(unreviewed, [])

    def test_admitted_rows_avoid_360_product_ids_and_non_dualsense_backbone(
        self,
    ) -> None:
        # Linux xpad legitimately binds PDP 0e6f:02a0/02a1 to GIP, so check what SDL
        # itself would admit, with only Microsoft rows treated as already catalogued.
        microsoft = {
            key: record["protocol"]["family"]
            for key, record in committed_records().items()
            if key[0] == catalog.MICROSOFT_VENDOR_ID
        }
        records, _ = catalog.build_sdl_records(self.rows, microsoft)
        families = {
            key: record["protocol"]["family"] for key, record in records.items()
        }
        self.assertEqual(
            [
                key
                for key, family in families.items()
                if family == "xbox.gip"
                and key[1] in catalog.MICROSOFT_XBOX_360_PRODUCT_IDS
            ],
            [],
        )
        self.assertEqual(families.get((0x358A, 0x0304)), "hid.descriptor")
        self.assertTrue(set(records) <= set(committed_records()))

    def test_real_exclusions_hold_and_every_admissible_row_is_committed(self) -> None:
        existing = {
            key: record["protocol"]["family"]
            for key, record in committed_records().items()
        }
        records, counts = catalog.build_sdl_records(self.rows, existing)
        self.assertEqual(records, {})
        excluded = {
            reason
            if reason == catalog.INTERFACE_SIGNATURE_BUCKET
            else f"excluded:{reason}"
            for key, (_, reason) in catalog.SDL_EXCLUSIONS.items()
            if key not in existing
        }
        self.assertTrue(excluded <= set(counts))
