from __future__ import annotations

import unittest
from typing import Any

from Scripts.Catalog import validate_profiles


def record(protocol: dict[str, Any], **fields: Any) -> dict[str, Any]:
    return {
        "$schema": validate_profiles.load_object(validate_profiles.SCHEMA_PATH)["$id"],
        "vendorID": 0x045E,
        "productID": 0x02EA,
        "protocol": protocol,
        **fields,
    }


GIP = {"family": "xbox.gip"}
XUSB = {"family": "xbox.xusb", "variant": "wired"}
DUALSENSE = {"family": "sony.dualsense"}


class ControllerSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_current_vocabulary(self) -> None:
        current = {
            "GIP quirk, actions and capabilities": record(
                {
                    **GIP,
                    "quirks": ["share-offset"],
                    "initialization": ["xbox.gip/hori-ack", "xbox.gip/power-on"],
                },
                usb={"configuration": "set1-before-claim"},
                capabilities={
                    "absent": ["left-trigger", "right-trigger"],
                    "rumble": "absent",
                },
            ),
            "Joy-Con side": record(
                {"family": "nintendo.switch1", "quirks": ["joy-con-left"]}
            ),
            "Switch 2 Joy-Con": record(
                {"family": "nintendo.switch1", "quirks": ["switch-2", "joy-con-right"]}
            ),
            "Switch 2 GameCube": record(
                {"family": "nintendo.switch1", "quirks": ["switch-2", "gamecube"]}
            ),
            "DualSense Edge controls": record(
                DUALSENSE,
                capabilities={
                    "present": [
                        "paddle-left-1",
                        "paddle-right-1",
                        "auxiliary-1",
                        "auxiliary-2",
                    ]
                },
            ),
            "GameSir inner grips": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "quirks": ["inner-grips"],
                }
            ),
            "GameSir lighting slots": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "quirks": ["lighting-slots"],
                }
            ),
            "GameSir vendor USB endpoints": record(
                {"family": "vendor.gamesir", "variant": "usb"},
                usb={"endpoints": {"in": 131, "out": 3}},
            ),
            "XUSB receiver": record({"family": "xbox.xusb", "variant": "receiver"}),
            "XID gamepad": record({"family": "xbox.xid", "variant": "gamepad"}),
            "Steam dongle": record(
                {"family": "valve.steam-controller", "variant": "dongle"}
            ),
            "descriptor HID": record({"family": "hid.descriptor"}),
        }
        for name, document in current.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_removed_vocabulary(self) -> None:
        removed = {
            "legacy driver": record({"driver": "GIP", "variant": "xboxOne"}),
            "legacy variant": record({**GIP, "variant": "xboxOne"}),
            "legacy XUSB variant": record(
                {"family": "xbox.xusb", "variant": "xbox360"}
            ),
            "transport field": record(GIP, transport="usb"),
            "Steam wirelessReceiver quirk": record(
                {
                    "family": "valve.steam-controller",
                    "variant": "wired",
                    "quirks": ["wirelessReceiver"],
                }
            ),
            "unknown family": record({"family": "xbox.adaptive-joystick"}),
            "binding string as family": record({"family": "xbox.xusb:wired"}),
            "missing stored variant": record({"family": "xbox.xusb"}),
            "transport variant stored": record({**DUALSENSE, "variant": "usb"}),
            "variant of another family": record(
                {"family": "xbox.xusb", "variant": "dongle"}
            ),
            "usb block on HID family": record(
                DUALSENSE, usb={"configuration": "set1-before-claim"}
            ),
            "usb block on GameSir enhanced HID": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "quirks": ["inner-grips"],
                },
                usb={"configuration": "set1-before-claim"},
            ),
            "GameSir enhanced HID without a model quirk": record(
                {"family": "vendor.gamesir", "variant": "enhanced-hid"}
            ),
            "GameSir enhanced HID with both model quirks": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "quirks": ["inner-grips", "lighting-slots"],
                }
            ),
            "GameSir vendor USB inner grips": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "usb",
                    "quirks": ["inner-grips"],
                }
            ),
            "GameSir vendor USB lighting slots": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "usb",
                    "quirks": ["lighting-slots"],
                }
            ),
            "unconsumed GIP quirk": record({**GIP, "quirks": ["sticksToNull"]}),
            "GameSir quirk on GIP": record({**GIP, "quirks": ["inner-grips"]}),
            "DS4 quirk": record({"family": "sony.dualshock4", "quirks": ["gyro"]}),
            "usb interface": record(GIP, usb={"interface": 1}),
            "startupPackets": record({**GIP, "startupPackets": ["xbox.gip/power-on"]}),
            "camelCase action": record({**GIP, "initialization": ["powerOn"]}),
            "XUSB initialization": record(
                {**XUSB, "initialization": ["xbox.gip/power-on"]}
            ),
            "both Joy-Con sides": record(
                {
                    "family": "nintendo.switch1",
                    "quirks": ["joy-con-left", "joy-con-right"],
                }
            ),
            "GameCube without Switch 2": record(
                {"family": "nintendo.switch1", "quirks": ["gamecube"]}
            ),
            "Switch 2 with two layouts": record(
                {
                    "family": "nintendo.switch1",
                    "quirks": ["switch-2", "gamecube", "joy-con-left"],
                }
            ),
            "Switch 2 input-only": record(
                {"family": "nintendo.switch1", "quirks": ["switch-2", "input-only"]}
            ),
            "Bluetooth-only with a layout": record(
                {
                    "family": "nintendo.switch1",
                    "quirks": ["bluetooth-only", "joy-con-left"],
                }
            ),
            "XUSB rumble absence": record(XUSB, capabilities={"rumble": "absent"}),
            "unknown control": record(GIP, capabilities={"absent": ["leftTrigger"]}),
            "empty capabilities": record(GIP, capabilities={}),
            "present on GIP": record(GIP, capabilities={"present": ["paddle-left-1"]}),
            "partial Edge controls": record(
                DUALSENSE, capabilities={"present": ["paddle-left-1", "auxiliary-1"]}
            ),
        }
        for protocol, quirks in (
            (GIP, ["shareOffset", "triggersToButtons", "inputOnly"]),
            (XUSB, ["dpadToButtons", "triggersToButtons"]),
            (
                {"family": "xbox.xid", "variant": "gamepad"},
                ["dpadToButtons", "sticksToNull", "triggersToButtons"],
            ),
            (DUALSENSE, ["edgeButtons", "microphoneMute", "touchpad"]),
            (
                {"family": "valve.steam-controller", "variant": "wired"},
                ["lizardMode", "trackpads"],
            ),
            (
                {"family": "nintendo.switch1"},
                ["usbHandshake", "joyConLeft", "joyConRight"],
            ),
        ):
            for quirk in quirks:
                removed[f"{protocol['family']} {quirk}"] = record(
                    {**protocol, "quirks": [quirk]}
                )
        for variant in ("gameSirG7ProUSB", "gameSirEnhancedHID", "enhanced-hid-8k"):
            removed[variant] = record({"family": "vendor.gamesir", "variant": variant})
        for name, document in removed.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))

    def test_rejects_protocol_default_endpoints(self) -> None:
        defaults = (
            (GIP, 130, 2),
            (XUSB, 129, 1),
            ({"family": "xbox.xid", "variant": "gamepad"}, 129, 2),
            ({"family": "vendor.gamesir", "variant": "usb"}, 130, 2),
        )
        for protocol, endpoint_in, endpoint_out in defaults:
            with self.subTest(protocol["family"]):
                self.assertFalse(
                    self.validator.is_valid(
                        record(
                            protocol,
                            usb={"endpoints": {"in": endpoint_in, "out": endpoint_out}},
                        )
                    )
                )
                self.assertTrue(
                    self.validator.is_valid(
                        record(protocol, usb={"endpoints": {"in": 131, "out": 3}})
                    )
                )


THIRD_PARTY = {"family": "vendor.ps3-third-party"}
GP100_RUMBLE = {
    "report": {"kind": "output", "id": 2, "length": 8},
    "leftMain": {"byte": 3},
    "rightMain": {"byte": 2},
}


class OwnershipAndOutputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_ownership_and_rumble_template(self) -> None:
        accepted = {
            "third-party rumble": record(THIRD_PARTY, output={"rumble": GP100_RUMBLE}),
            "OJD ownership": record(THIRD_PARTY, ownership="ojd"),
            "macOS ownership": record(DUALSENSE, ownership="macos"),
            "feature report": record(
                THIRD_PARTY,
                output={
                    "rumble": {
                        "report": {"kind": "feature", "id": 0, "length": 2},
                        "rightTrigger": {"byte": 1},
                    }
                },
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_ownership_and_output(self) -> None:
        report = GP100_RUMBLE["report"]
        rejected = {
            "unknown ownership": record(THIRD_PARTY, ownership="native"),
            "GIP ownership": record(GIP, ownership="ojd"),
            "XUSB ownership": record(XUSB, ownership="macos"),
            "GameSir USB ownership": record(
                {"family": "vendor.gamesir", "variant": "usb"}, ownership="ojd"
            ),
            "template on DualSense": record(DUALSENSE, output={"rumble": GP100_RUMBLE}),
            "input report": record(
                THIRD_PARTY,
                output={
                    "rumble": {
                        "report": {**report, "kind": "input"},
                        "leftMain": {"byte": 3},
                    }
                },
            ),
            "no motor": record(THIRD_PARTY, output={"rumble": {"report": report}}),
            "haptic motor": record(
                THIRD_PARTY,
                output={"rumble": {"report": report, "leftHaptic": {"byte": 3}}},
            ),
            "unknown template": record(
                THIRD_PARTY, output={"rumble": GP100_RUMBLE, "lighting": {}}
            ),
            "empty output": record(THIRD_PARTY, output={}),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


REPORT_LAYOUT = {"family": "hid.report-layout"}
BUTTON = {"control": "face-south", "byte": 1, "mask": 1}
LAYOUT = {"report": {"length": 2}, "buttons": [BUTTON]}


class InputLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_report_layouts_and_dpad_pressure(self) -> None:
        accepted = {
            "one button": record(REPORT_LAYOUT, input=LAYOUT),
            "every section": record(
                REPORT_LAYOUT,
                input={
                    "report": {"id": 1, "length": 8},
                    "buttons": [BUTTON],
                    "axes": [
                        {
                            "control": "left-stick-x",
                            "byte": 2,
                            "bits": 16,
                            "signed": True,
                        },
                        {"control": "left-stick-y", "byte": 4, "inverted": True},
                    ],
                    "hat": [
                        {
                            "encoding": "8-way",
                            "byte": 5,
                            "mask": 240,
                            "neutralUntilNonzero": True,
                        },
                        {
                            "encoding": "directions",
                            "up": {"byte": 6, "mask": 1},
                            "right": {"byte": 6, "mask": 2},
                            "down": {"byte": 6, "mask": 4},
                            "left": {"byte": 6, "mask": 8},
                        },
                    ],
                    "leftTrigger": {"byte": 7},
                    "rightTrigger": {"button": {"byte": 1, "mask": 2}},
                },
            ),
            "layout with rumble": record(
                REPORT_LAYOUT, input=LAYOUT, output={"rumble": GP100_RUMBLE}
            ),
            "dpad pressure": record({**THIRD_PARTY, "quirks": ["dpad-pressure"]}),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_report_layouts(self) -> None:
        rejected = {
            "missing input": record(REPORT_LAYOUT),
            "input on another family": record(THIRD_PARTY, input=LAYOUT),
            "report ID 0": record(
                REPORT_LAYOUT, input={**LAYOUT, "report": {"id": 0, "length": 2}}
            ),
            "long report": record(
                REPORT_LAYOUT, input={**LAYOUT, "report": {"length": 65}}
            ),
            "report only": record(REPORT_LAYOUT, input={"report": {"length": 2}}),
            "empty buttons": record(REPORT_LAYOUT, input={**LAYOUT, "buttons": []}),
            "zero mask": record(
                REPORT_LAYOUT, input={**LAYOUT, "buttons": [{**BUTTON, "mask": 0}]}
            ),
            "dpad button": record(
                REPORT_LAYOUT,
                input={**LAYOUT, "buttons": [{**BUTTON, "control": "dpad"}]},
            ),
            "12-bit axis": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "axes": [{"control": "left-stick-x", "byte": 1, "bits": 12}],
                },
            ),
            "4-way hat": record(
                REPORT_LAYOUT,
                input={**LAYOUT, "hat": [{"encoding": "4-way", "byte": 1, "mask": 15}]},
            ),
            "empty trigger": record(REPORT_LAYOUT, input={**LAYOUT, "leftTrigger": {}}),
            "unknown section": record(REPORT_LAYOUT, input={**LAYOUT, "touchpad": {}}),
            "dpad pressure elsewhere": record(
                {**DUALSENSE, "quirks": ["dpad-pressure"]}
            ),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


class CapabilityOverlapTests(unittest.TestCase):
    def test_validator_rejects_overlapping_capabilities(self) -> None:
        import json
        import tempfile
        from pathlib import Path

        overlapping = record(
            DUALSENSE,
            capabilities={
                "absent": ["paddle-left-1"],
                "present": [
                    "paddle-left-1",
                    "paddle-right-1",
                    "auxiliary-1",
                    "auxiliary-2",
                ],
            },
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(overlapping))
            with self.assertRaises(validate_profiles.ValidationError):
                validate_profiles.validate_record(path, enforce_path=False)


if __name__ == "__main__":
    unittest.main()
