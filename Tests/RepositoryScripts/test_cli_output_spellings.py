import unittest
from typing import Any

from Scripts.Quality import repository_tool, validate_schemas

SCHEMA = "cli-output.schema.json"
VERSION = "openjoystickdriver/v1alpha3"
INTENSITIES = {
    key: 0
    for key in (
        "lowFrequency",
        "highFrequency",
        "leftTrigger",
        "rightTrigger",
        "leftHaptic",
        "rightHaptic",
    )
}

D = "/$defs"
OWNERSHIP = f"{D}/controllerShow/properties/ownership/properties"
PERMISSIONS = f"{D}/sharedPermissions/properties/permissions/items/properties"
STATUS = f"{D}/status/properties"
EXTENSION = f"{STATUS}/transportExtension/properties"
BUNDLE = ("Present", "Missing", "Invalid")
REGISTRATION = ("Active", "Inactive", "Absent", "Unavailable")
LAYERS = ("Bundled", "Package", "User")
PERMISSION_STATES = ("Granted", "Denied", "Unknown")
OUTCOMES = (
    "Delivered",
    "NotFound",
    "UnsupportedCapability",
    "NotReady",
    "InvalidValue",
    "WriteFailed",
    "Cancelled",
)
LOG_STREAMS = ("StandardOutput", "StandardError")

# pointer -> the values the schema lists. Each value in its first-letter-lowercase form, and
# the lowercase kebab-case form, is not a value.
VALUES: dict[str, tuple[str, ...]] = {
    f"{D}/configShow/properties/values/items/properties/layer": (
        "Driver",
        "Bundled",
        "Package",
        "Global",
        "User",
        "Profile",
    ),
    f"{D}/controllerCapture/properties/direction": ("Rx", "Tx"),
    f"{OWNERSHIP}/discoverySource": ("HID", "RawUSB"),
    f"{OWNERSHIP}/duplicateExposureRisk": (
        "None",
        "SystemHIDVisible",
        "UpstreamVirtualDevice",
        "SystemGameController",
        "UnknownOwnership",
    ),
    f"{OWNERSHIP}/hidInput": (
        "Unknown",
        "Exclusive",
        "Shared",
        "AccessDenied",
        "OwnedByAnotherClient",
        "AcquisitionFailed",
    ),
    f"{OWNERSHIP}/physical": (
        "ExclusiveHID",
        "ExclusiveRawUSB",
        "UpstreamVirtualDevice",
        "Unknown",
    ),
    f"{OWNERSHIP}/serverSource": ("Bundled", "Package", "User", "Default", "Route"),
    f"{D}/controllerShow/properties/publication/properties/state": (
        "Published",
        "NotPublished",
        "Failed",
    ),
    f"{D}/controllerShow/properties/publication/properties/reason": (
        "OutputDisabled",
        "SystemGamepad",
        "NativeHIDPassThrough",
        "UpstreamVirtualDevice",
        "SessionSuspended",
        "NoVirtualProfile",
        "Suppressed",
        "NoInputYet",
        "HeldByAnotherClient",
    ),
    f"{D}/controllerShow/properties/record/properties/layer": LAYERS,
    f"{D}/controllerShow/properties/serving/properties/reason": (
        "UserDisabled",
        "UpstreamVirtualDevice",
        "NoVirtualProfile",
    ),
    f"{D}/controllerShow/properties/virtual/properties/overrideScope": (
        "Unit",
        "Model",
    ),
    f"{D}/virtualShow/properties/controllers/items/properties/overrideScope": (
        "Unit",
        "Model",
    ),
    f"{D}/diagnose/properties/checks/items/properties/status": (
        "Pass",
        "Warn",
        "Fail",
        "Skip",
    ),
    f"{D}/logShow/oneOf/1/properties/stream": LOG_STREAMS,
    f"{D}/logShow/oneOf/0/properties/logs/items/properties/stream": LOG_STREAMS,
    f"{D}/recordDraft/properties/operation": ("Add", "Patch"),
    f"{D}/sharedRecordValidation/properties/operation": ("Add", "Patch"),
    f"{D}/recordList/properties/items/items/properties/layer": LAYERS,
    f"{D}/recordShow/properties/fields/additionalProperties": LAYERS,
    f"{D}/recordShow/properties/layer": LAYERS,
    f"{D}/recordShow/properties/transport": ("HID", "USB"),
    f"{D}/sharedRecordValidation/properties/transport": ("HID", "USB"),
    f"{D}/recordShow/properties/transportClaim": ("Claimed", "Unclaimed"),
    f"{D}/sharedRecordValidation/properties/transportClaim": ("Claimed", "Unclaimed"),
    f"{D}/sharedControllerOutput/properties/results/items/properties/outcome": OUTCOMES,
    f"{PERMISSIONS}/id": ("InputRead", "InputInject", "USBTransport"),
    f"{PERMISSIONS}/state": PERMISSION_STATES,
    f"{STATUS}/permissions/properties/inputRead": PERMISSION_STATES,
    f"{STATUS}/permissions/properties/inputInject": PERMISSION_STATES,
    f"{D}/sharedProfileIssue/properties/kind": ("DamagedProfile", "UnusableLibrary"),
    f"{D}/sharedServiceState/properties/state": ("Running", "Stopped"),
    f"{STATUS}/service/properties/state": ("Running", "Stopped"),
    f"{D}/sharedTransportExtensionState/properties/state": (
        "Active",
        "Inactive",
        "AwaitingApproval",
    ),
    f"{STATUS}/commandLineTool/properties/state": (
        "Installed",
        "LinkedElsewhere",
        "Broken",
        "BlockedByFile",
        "Missing",
    ),
    f"{EXTENSION}/bundle": BUNDLE,
    f"{EXTENSION}/registration": REGISTRATION,
    f"{D}/transportExtensionStatus/properties/bundle": BUNDLE,
    f"{D}/transportExtensionStatus/properties/registration": REGISTRATION,
    f"{D}/updateCheck/properties/status": (
        "UpToDate",
        "Available",
        "AheadOfLatestRelease",
    ),
    f"{D}/virtualExportMapping/properties/format": ("SDL", "W3C"),
}


def lower_first(value: str) -> str:
    return value[0].lower() + value[1:]


class CliOutputSpellingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # The kebab-case spelling is what `CommandLineName.kebab` prints for a value, so the
        # refused spelling is the one `ojd` accepts as an argument.
        cls.kebab = repository_tool.kebab(
            sorted({value for values in VALUES.values() for value in values})
        )

    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.schema: dict[str, Any] = documents[SCHEMA]
        self.registry = validate_schemas.schema_registry(documents)

    def accepts(self, pointer: str, value: Any) -> bool:
        return validate_schemas.Draft202012Validator(
            {"$ref": f"#{pointer}", "$defs": self.schema["$defs"]},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        ).is_valid(value)

    def test_a_refused_token_takes_the_transport_in_upper_camel_case(self) -> None:
        token = {
            "reason": "E1002",
            "refusalTime": "2026-01-01T00:00:00Z",
            "scopes": ["Read"],
            "transport": "Web",
        }
        self.assertTrue(self.accepts("/$defs/sharedAccessRefusedToken", token))
        for transport in ("socket", "web"):
            with self.subTest(transport=transport):
                self.assertFalse(
                    self.accepts(
                        "/$defs/sharedAccessRefusedToken",
                        {**token, "transport": transport},
                    )
                )
        self.assertFalse(
            self.accepts(
                "/$defs/sharedAccessRefusedToken", {**token, "scopes": ["read"]}
            )
        )

    def test_a_virtual_feed_line_takes_the_rumble_types_in_upper_camel_case(
        self,
    ) -> None:
        header = {"apiVersion": VERSION, "kind": "RumbleCommand"}
        line = "/$defs/sharedVirtualFeedLine"
        self.assertTrue(
            self.accepts(
                line, {**header, "type": "SetRumble", "intensities": INTENSITIES}
            )
        )
        self.assertTrue(self.accepts(line, {**header, "type": "StopRumble"}))
        for type_name in ("setRumble", "stopRumble"):
            with self.subTest(type=type_name):
                self.assertFalse(
                    self.accepts(
                        line, {**header, "type": type_name, "intensities": INTENSITIES}
                    )
                )
        self.assertFalse(
            self.accepts(
                line,
                {
                    **header,
                    "type": "SetRumble",
                    "intensities": {**INTENSITIES, "leftMain": 0},
                },
            )
        )

    def test_a_publication_carries_a_reason_or_a_failure_text_by_state(self) -> None:
        publication = "/$defs/controllerShow/properties/publication"
        cases = (
            ({"state": "Published"}, True),
            ({"state": "NotPublished", "reason": "NoInputYet"}, True),
            ({"state": "Failed", "failure": "send failed"}, True),
            ({"state": "NotPublished"}, False),
            ({"state": "NotPublished", "reason": "send failed"}, False),
            ({"state": "NotPublished", "reason": "NoInputYet", "failure": "x"}, False),
            ({"state": "Failed"}, False),
            ({"state": "Failed", "failure": ""}, False),
            ({"state": "Failed", "reason": "NoInputYet", "failure": "x"}, False),
            ({"state": "Published", "reason": "NoInputYet"}, False),
            ({"state": "Published", "failure": "x"}, False),
        )
        for value, valid in cases:
            with self.subTest(value=value):
                self.assertEqual(self.accepts(publication, value), valid)

    def test_acronym_values_take_the_acronym_in_upper_case(self) -> None:
        ownership = "/$defs/controllerShow/properties/ownership/properties"
        cases = (
            (f"{ownership}/physical", "ExtensionOwnedUSB", "ExtensionOwnedUsb"),
            (f"{ownership}/physical", "SystemHIDVisible", "SystemHidVisible"),
            (
                f"{ownership}/duplicateExposureRisk",
                "SystemHIDVisible",
                "SystemHidVisible",
            ),
            (
                "/$defs/controllerShow/properties/serving/properties/route",
                "VirtualHID",
                "VirtualHid",
            ),
        )
        for pointer, current, replaced in cases:
            with self.subTest(pointer=pointer, value=current):
                self.assertTrue(self.accepts(pointer, current))
                self.assertFalse(self.accepts(pointer, replaced))

    def test_every_listed_value_is_upper_camel_case_and_its_earlier_spellings_are_not(
        self,
    ) -> None:
        for pointer, values in VALUES.items():
            for value in values:
                with self.subTest(pointer=pointer, value=value):
                    self.assertTrue(self.accepts(pointer, value))
                    for refused in {
                        lower_first(value),
                        self.kebab[value],
                        value.lower(),
                    } - {value}:
                        self.assertFalse(self.accepts(pointer, refused), refused)

    def test_the_reset_detail_takes_All(self) -> None:
        pointer = f"{D}/virtualReset/oneOf/0/properties/details/properties/reset"
        self.assertTrue(self.accepts(pointer, "All"))
        self.assertFalse(self.accepts(pointer, "all"))

    def test_the_permission_ids_are_not_the_kebab_case_names(self) -> None:
        pointer = f"{PERMISSIONS}/id"
        for refused in ("input-read", "input-inject", "usb-transport", "usbTransport"):
            with self.subTest(value=refused):
                self.assertFalse(self.accepts(pointer, refused))


if __name__ == "__main__":
    unittest.main()
