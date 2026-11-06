from __future__ import annotations

import hashlib
import io
import json
import pathlib
import tempfile
import unittest
import urllib.error
from email.message import Message
from typing import Any, ClassVar
from unittest.mock import patch

from Scripts.Catalog import generate_controller_catalog as catalog
from Scripts.Catalog import generate_xpad_records as xpad
from Scripts.Catalog.schema_header import header


def hid_source(vendor: str, product: str) -> str:
    return f"static const struct hid_device_id ids[] = {{ HID_USB_DEVICE({vendor}, {product}) }};"


def proto(record: dict[str, Any]) -> dict[str, Any]:
    """The protocol of a record's default mode."""
    return next(mode for mode in record["modes"] if mode["id"] == "default")["protocol"]


class CatalogGenerationTests(unittest.TestCase):
    def test_a_failed_download_stops_with_its_url_and_status(self) -> None:
        rate_limit = urllib.error.HTTPError(
            "https://raw.githubusercontent.com",
            429,
            "Too Many Requests",
            Message(),
            None,
        )
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(catalog, "source_cache", return_value=pathlib.Path(directory)),
            patch.object(catalog.urllib.request, "urlopen", side_effect=rate_limit),
            self.assertRaisesRegex(
                catalog.CatalogError,
                "raw.githubusercontent.com/torvalds/linux/a{40}/"
                "drivers/input/joystick/xpad.c failed: HTTP 429",
            ),
        ):
            catalog.load_locked_files(
                self.locked("static const int xpad_device[] = {0};\n")
            )

    def locked(self, source: str) -> dict[str, Any]:
        return {
            "repository": "torvalds/linux",
            "commit": "a" * 40,
            "files": {
                "xpad": {
                    "path": "drivers/input/joystick/xpad.c",
                    "sha256": hashlib.sha256(source.encode()).hexdigest(),
                }
            },
        }

    def test_a_downloaded_source_is_cached_and_read_back_without_the_network(
        self,
    ) -> None:
        source = "static const int xpad_device[] = {1};\n"
        linux = self.locked(source)

        with tempfile.TemporaryDirectory() as directory:
            cache = pathlib.Path(directory)
            with (
                patch.object(catalog, "source_cache", return_value=cache),
                patch.object(
                    catalog.urllib.request,
                    "urlopen",
                    return_value=io.BytesIO(source.encode()),
                ),
            ):
                self.assertEqual(catalog.load_locked_files(linux), {"xpad": source})
            digest = linux["files"]["xpad"]["sha256"]
            self.assertEqual((cache / digest).read_text(), source)

            with (
                patch.object(catalog, "source_cache", return_value=cache),
                patch.object(catalog.urllib.request, "urlopen") as urlopen,
            ):
                self.assertEqual(catalog.load_locked_files(linux), {"xpad": source})
            urlopen.assert_not_called()

    def test_a_cached_source_that_fails_its_hash_is_refused(self) -> None:
        linux = self.locked("static const int xpad_device[] = {2};\n")
        with tempfile.TemporaryDirectory() as directory:
            cache = pathlib.Path(directory)
            digest = linux["files"]["xpad"]["sha256"]
            (cache / digest).write_text("changed\n")
            with (
                patch.object(catalog, "source_cache", return_value=cache),
                patch.object(catalog.urllib.request, "urlopen") as urlopen,
                self.assertRaisesRegex(catalog.CatalogError, str(cache / digest)),
            ):
                catalog.load_locked_files(linux)
            urlopen.assert_not_called()


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
        self.assertEqual(proto(profile), {"family": "XboxXID", "variant": "Gamepad"})
        self.assertNotIn("transport", profile)
        self.assertEqual(
            profile["capabilities"],
            {
                "absent": [
                    "LeftStickX",
                    "LeftStickY",
                    "RightStickX",
                    "RightStickY",
                    "LeftTrigger",
                    "RightTrigger",
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
            proto(candidates[0].profile),
            {
                "family": "XboxGIP",
                "initialization": ["XboxGIP/power-on"],
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
            proto(profile),
            {
                "family": "XboxGIP",
                "parameters": {"shareButton": {"fromEnd": 26}},
                "initialization": [
                    "XboxGIP/power-on",
                    "XboxGIP/s-init",
                    "XboxGIP/led-on",
                    "XboxGIP/auth-done",
                ],
            },
        )
        self.assertNotIn("capabilities", profile)

    def test_gip_share_button_reads_eighteen_bytes_from_the_end(self) -> None:
        profile = xpad.build_profile(
            self.device("XTYPE_XBOXONE", "MAP_SHARE_BUTTON"),
            [
                xpad.InitRule(0, 0, "xboxone_power_on"),
                xpad.InitRule(0, 0, "xboxone_led_on"),
                xpad.InitRule(0, 0, "xboxone_auth_done"),
            ],
        )
        self.assertEqual(
            proto(profile),
            {"family": "XboxGIP", "parameters": {"shareButton": {"fromEnd": 18}}},
        )

    def test_parameter_outside_its_driver_is_rejected(self) -> None:
        with self.assertRaises(xpad.GenerationError):
            xpad.build_profile(
                self.device("XTYPE_XBOX360", "MAP_SHARE_OFFSET"), init_rules=[]
            )

    def test_xpad_types_map_to_family_and_stored_variant(self) -> None:
        expected = {
            "XTYPE_XBOX": {"family": "XboxXID", "variant": "Gamepad"},
            "XTYPE_XBOX360": {"family": "XboxXUSB", "variant": "Wired"},
            "XTYPE_XBOX360W": {"family": "XboxXUSB", "variant": "Receiver"},
        }
        for xtype, protocol in expected.items():
            with self.subTest(xtype):
                profile = xpad.build_profile(self.device(xtype, "0"), init_rules=[])
                self.assertEqual(proto(profile), protocol)


class HIDRecordTests(unittest.TestCase):
    def test_steam_receiver_is_the_dongle_variant_without_parameters(self) -> None:
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
            proto(records[0]),
            {"family": "ValveSteamController", "variant": "Dongle"},
        )
        self.assertNotIn("transport", records[0])


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
            "PS3Controller": {"family": "SonySixaxis"},
            "PS4Controller": {"family": "SonyDualShock4"},
            "PS5Controller": {"family": "SonyDualSense"},
            "SwitchProController": {"family": "NintendoSwitch1"},
            "XBox360Controller": {"family": "XboxXUSB", "variant": "Wired"},
            "XBoxOneController": {"family": "XboxGIP"},
            "SwitchInputOnlyController": {"family": "NintendoSwitchInputOnly"},
        }
        for controller_type, protocol in expected.items():
            with self.subTest(controller_type):
                records, counts = self.build([(0x054C, 0x1234, controller_type)])
                self.assertEqual(proto(records[(0x054C, 0x1234)]), protocol)
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
        protocols = {key[1]: proto(record) for key, record in records.items()}
        steam = "ValveSteamController"
        triton = "ValveSteamTriton"
        wired = {"family": steam, "variant": "Wired"}
        ble = {"family": steam, "variant": "BluetoothLE"}
        self.assertEqual(
            protocols,
            {
                0x1101: wired,
                0x1105: ble,
                0x1106: ble,
                0x1201: wired,
                0x1202: ble,
                0x1205: {"family": "ValveSteamDeck"},
                0x1302: {"family": triton, "variant": "Wired"},
                0x1303: {"family": triton, "variant": "BluetoothLE"},
                0x1304: {"family": triton, "variant": "Dongle"},
                0x1305: {"family": triton, "variant": "Dongle"},
            },
        )
        self.assertEqual(counts, {"added": 10})

    def test_switch_2_rows_use_the_switch_2_family_with_the_side_layout(self) -> None:
        rows = [
            (0x057E, 0x2006, "SwitchJoyConLeft"),
            (0x057E, 0x2066, "SwitchJoyConRight"),
            (0x057E, 0x2067, "SwitchJoyConLeft"),
            (0x057E, 0x2069, "SwitchProController"),
        ]
        records, counts = self.build(rows)
        protocols = {key[1]: proto(record) for key, record in records.items()}
        switch = "NintendoSwitch1"
        switch2 = "NintendoSwitch2"
        self.assertEqual(
            protocols,
            {
                0x2006: {"family": switch, "parameters": {"layout": "JoyConLeft"}},
                0x2066: {"family": switch2, "parameters": {"layout": "JoyConRight"}},
                0x2067: {"family": switch2, "parameters": {"layout": "JoyConLeft"}},
                0x2069: {"family": switch2},
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
            proto(records[(0x0955, 0x7210)]), {"family": "VendorNVIDIAShield"}
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
            (0x045E, 0x028E): "XboxXUSB",
            (0x28DE, 0x1102): "ValveSteamController",
            (0x0E6F, 0x0147): "XboxGIP",
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
                catalog.build_sdl_records(rows, {(0x057E, 0x2069): "NintendoSwitch1"})

    def test_add_override_wins_over_an_sdl_identity(self) -> None:
        override = {
            **header("Controller"),
            "vendorID": 0x1532,
            "productID": 0x1000,
            "modes": [{"id": "default", "protocol": {"family": "HIDDescriptor"}}],
        }
        adds = {(0x1532, 0x1000): override}
        records: dict[tuple[int, int], dict[str, object]] = {}
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", {}),
        ):
            counts = catalog.merge_sdl_records(
                records, adds, [(0x1532, 0x1000, "PS4Controller")]
            )
        self.assertEqual(counts, {"conflict": 1})
        self.assertEqual(records, {})

    def test_an_authored_record_may_not_take_an_upstream_identity(self) -> None:
        record: dict[str, object] = {"vendorID": 1, "productID": 2}
        with self.assertRaises(catalog.CatalogError):
            catalog.apply_built_in_patches({(1, 2): record}, {(1, 2): record})

    def test_a_tool_refusal_is_a_catalog_error(self) -> None:
        refusal = catalog.repository_tool.ToolError("E5007: a.json: refused")
        with (
            patch.object(catalog.repository_tool, "check", side_effect=refusal),
            self.assertRaisesRegex(catalog.CatalogError, "refused"),
        ):
            catalog.apply_built_in_patches({}, {})

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
            proto(records[(0x1532, 0x100B)]),
            {"family": "SonyDualSense", "parameters": {"maker": "ThirdParty"}},
        )
        self.assertEqual(proto(records[(0x054C, 0x0CE6)]), {"family": "SonyDualSense"})
        self.assertEqual(counts, {"added": 3, "interface-signature": 2})

    def test_third_party_ps3_rows_bind_the_third_party_family(self) -> None:
        records, counts = self.build(
            [(0x0738, 0x3250, "PS3Controller"), (0x054C, 0x0268, "PS3Controller")]
        )
        self.assertEqual(
            proto(records[(0x0738, 0x3250)]), {"family": "VendorPS3ThirdParty"}
        )
        self.assertEqual(proto(records[(0x054C, 0x0268)]), {"family": "SonySixaxis"})
        self.assertEqual(counts, {"added": 2})

    def test_identity_families_override_the_type_and_must_stay_listed(self) -> None:
        overrides = {
            (0x2563, 0x0523): ("PS3Controller", "SonySixaxis", None),
            (0x0F0D, 0x0086): ("PS3Controller", "XboxXUSB", "Wired"),
        }
        rows = [(0x2563, 0x0523, "PS3Controller"), (0x0F0D, 0x0086, "PS3Controller")]
        with (
            patch.object(catalog, "SDL_EXCLUSIONS", {}),
            patch.object(catalog, "SDL_IDENTITY_FAMILIES", overrides),
        ):
            records, counts = catalog.build_sdl_records(rows, {})
            with self.assertRaises(catalog.CatalogError):
                catalog.build_sdl_records(rows[:1], {})
        self.assertEqual(proto(records[(0x2563, 0x0523)]), {"family": "SonySixaxis"})
        self.assertEqual(
            proto(records[(0x0F0D, 0x0086)]),
            {"family": "XboxXUSB", "variant": "Wired"},
        )
        self.assertEqual(counts, {"added": 2})

    def test_unreviewed_microsoft_xbox_one_row_fails_generation(self) -> None:
        with self.assertRaises(catalog.CatalogError):
            self.build([(0x045E, 0x0B99, "XBoxOneController")])
        records, counts = self.build(
            [(0x045E, 0x0B12, "XBoxOneController")], {(0x045E, 0x0B12): "XboxGIP"}
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
        self.assertEqual(proto(records[(0x358A, 0x0304)]), {"family": "HIDDescriptor"})

    def test_records_carry_no_provenance(self) -> None:
        records, _ = self.build([(0x1532, 0x1000, "PS4Controller")])
        self.assertEqual(
            set(records[(0x1532, 0x1000)]),
            {"apiVersion", "kind", "vendorID", "productID", "modes"},
        )


def committed_records() -> dict[tuple[int, int], dict[str, Any]]:
    records: dict[tuple[int, int], dict[str, Any]] = {}
    for path in sorted(catalog.OUTPUT_DIR.glob("*/*.json")):
        record = json.loads(path.read_text())
        records[catalog.record_key(record)] = record
    return records


class ProtocolCopyTests(unittest.TestCase):
    """`--check` compares the Kit bundle's protocol copies with the authored files."""

    def setUp(self) -> None:
        import tempfile
        from pathlib import Path

        directory = tempfile.TemporaryDirectory(prefix="ojd-catalog-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        self.authored = root / "Resources" / "Protocols"
        self.bundled = root / "Kit" / "Protocols"
        self.authored.mkdir(parents=True)
        (self.authored / "xbox-xid.json").write_text('{"family": "XboxXID"}\n')
        for name, value in (
            ("ROOT", root),
            ("OUTPUT_DIR", root / "Kit" / "Controllers"),
            ("PROTOCOL_DIR", self.authored),
            ("PROTOCOL_OUTPUT_DIR", self.bundled),
            ("VIRTUAL_DEVICE_DIR", root / "Resources" / "VirtualDevices"),
            ("VIRTUAL_DEVICE_OUTPUT_DIR", root / "Kit" / "VirtualDevices"),
            ("DATABASE_OUTPUT", root / "Kit" / "sdl-gamecontrollerdb.txt"),
        ):
            patcher = patch.object(catalog, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        catalog.write_catalog({})

    def assert_check_reports(self, detail: str) -> None:
        with self.assertRaisesRegex(catalog.CatalogError, detail):
            catalog.check_catalog({})

    def test_written_copies_pass_the_check(self) -> None:
        self.assertEqual(
            (self.bundled / "xbox-xid.json").read_text(), '{"family": "XboxXID"}\n'
        )
        catalog.check_catalog({})

    def test_a_missing_copy_is_reported(self) -> None:
        (self.bundled / "xbox-xid.json").unlink()
        self.assert_check_reports(r"missing Kit/Protocols/xbox-xid\.json")

    def test_a_stale_copy_is_reported(self) -> None:
        (self.bundled / "xbox.old.json").write_text("{}\n")
        self.assert_check_reports(r"stale Kit/Protocols/xbox\.old\.json")

    def test_a_changed_copy_is_reported(self) -> None:
        (self.bundled / "xbox-xid.json").write_text('{"family": "XboxXUSB"}\n')
        self.assert_check_reports(r"changed Kit/Protocols/xbox-xid\.json")

    def test_write_removes_a_stale_copy(self) -> None:
        (self.bundled / "xbox.old.json").write_text("{}\n")
        catalog.write_catalog({})
        self.assertEqual(
            sorted(path.name for path in self.bundled.iterdir()), ["xbox-xid.json"]
        )

    def test_write_refreshes_the_copies_before_the_records_are_built(self) -> None:
        (self.authored / "xbox-xid.json").write_text('{"family": "XboxXUSB"}\n')
        seen: list[str] = []
        builds: list[str] = []

        def build_catalog() -> dict[tuple[int, int], str]:
            catalog.repository_tool.binary()
            seen.append((self.bundled / "xbox-xid.json").read_text())
            return {}

        with (
            patch.object(catalog.repository_tool, "build", builds.append),
            patch.object(catalog, "build_catalog", build_catalog),
            patch("sys.argv", ["generate_controller_catalog.py", "--write"]),
            patch("sys.stdout", io.StringIO()),
        ):
            catalog.repository_tool.binary.cache_clear()
            catalog.repository_tool.binary()
            self.assertEqual(catalog.main(), 0)
        catalog.repository_tool.binary.cache_clear()
        self.assertEqual(seen, ['{"family": "XboxXUSB"}\n'])
        # The tool built at import ships the stale copies, so it is built again after them.
        self.assertEqual(builds, ["OJDRepositoryTool", "OJDRepositoryTool"])


class CommittedCatalogTests(unittest.TestCase):
    """Data-level invariants of the generated catalog; no network needed."""

    def setUp(self) -> None:
        self.records = committed_records()

    def test_backbone_one_ps5_v2_is_not_catalogued_as_dualsense(self) -> None:
        record = self.records.get((0x358A, 0x0304))
        if record is not None:
            self.assertEqual(proto(record)["family"], "HIDDescriptor")

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
            key: proto(record)["family"]
            for key, record in committed_records().items()
            if key[0] == catalog.MICROSOFT_VENDOR_ID
        }
        records, _ = catalog.build_sdl_records(self.rows, microsoft)
        families = {key: proto(record)["family"] for key, record in records.items()}
        self.assertEqual(
            [
                key
                for key, family in families.items()
                if family == "XboxGIP"
                and key[1] in catalog.MICROSOFT_XBOX_360_PRODUCT_IDS
            ],
            [],
        )
        self.assertEqual(families.get((0x358A, 0x0304)), "HIDDescriptor")
        self.assertTrue(set(records) <= set(committed_records()))

    def test_real_exclusions_hold_and_every_admissible_row_is_committed(self) -> None:
        existing = {
            key: proto(record)["family"] for key, record in committed_records().items()
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
