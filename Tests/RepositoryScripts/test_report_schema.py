from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path
from typing import Any, cast

from Scripts.Quality import validate_schemas

FIXTURE = (
    Path(__file__).resolve().parents[1]
    / "EquivalenceSnapshots"
    / "support-report-binding.json"
)


def load_fixture() -> dict[str, Any]:
    with FIXTURE.open(encoding="utf-8") as source:
        return json.load(source)


class ReportSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)
        self.validator = validate_schemas.Draft202012Validator(
            self.documents["report.schema.json"],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_accepts_a_report_with_a_bound_controller_and_a_rejected_candidate(
        self,
    ) -> None:
        report = load_fixture()
        controller = report["data"]["controllers"][0]
        self.assertTrue(controller["binding"]["interfaces"])
        unbound = report["data"]["unboundDevices"][0]
        self.assertTrue(unbound["binding"]["rejectedCandidates"])

        self.validator.validate(report)

    def test_accepts_the_five_stage_stamps_of_a_frame(self) -> None:
        report = load_fixture()
        stages = report["data"]["frameTimings"][0]["frames"][0]["stages"]
        self.assertEqual(
            [stage["stage"] for stage in stages],
            [
                "Read",
                "Parse",
                "Dispatch",
                "DeliveryVirtualDevice",
                "DeliveryEndpoint",
            ],
        )

        self.validator.validate(report)

    def test_rejects_a_permission_state_that_is_not_a_listed_value(self) -> None:
        for field in ("inputRead", "inputInject"):
            for state in ("granted", "denied", "unknown", "GRANTED", "", "Allowed"):
                with self.subTest(field=field, state=state):
                    report = copy.deepcopy(load_fixture())
                    report["data"]["permissions"][field] = state
                    with self.assertRaises(validate_schemas.ValidationError):
                        self.validator.validate(report)

    def test_rejects_an_unknown_frame_stage(self) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["frameTimings"][0]["frames"][0]["stages"][0]["stage"] = "wire"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_accepts_the_summary_of_a_frame_window(self) -> None:
        report = load_fixture()
        summary = report["data"]["frameTimings"][0]["summary"]
        self.assertEqual(summary["lastSeconds"], 10)
        self.assertEqual(summary["frames"], 120)
        self.assertEqual(summary["stalls"]["count"], 2)

        self.validator.validate(report)

    def test_rejects_a_summary_with_an_unknown_gap_a_window_out_of_range_or_no_size(
        self,
    ) -> None:
        unknown_gap = copy.deepcopy(load_fixture())
        unknown_gap["data"]["frameTimings"][0]["summary"]["gaps"][0]["gap"] = "wire"
        no_frames = copy.deepcopy(load_fixture())
        del no_frames["data"]["frameTimings"][0]["summary"]["frames"]
        no_summary = copy.deepcopy(load_fixture())
        del no_summary["data"]["frameTimings"][0]["summary"]
        out_of_range = []
        for seconds in (0, 16):
            report = copy.deepcopy(load_fixture())
            report["data"]["frameTimings"][0]["summary"]["lastSeconds"] = seconds
            out_of_range.append(report)

        for report in (unknown_gap, no_frames, no_summary, *out_of_range):
            with self.assertRaises(validate_schemas.ValidationError):
                self.validator.validate(report)

    def test_rejects_a_report_without_frame_timings(self) -> None:
        report = copy.deepcopy(load_fixture())
        del report["data"]["frameTimings"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_accepts_a_bluetooth_le_controller_on_a_gatt_link(self) -> None:
        report = copy.deepcopy(load_fixture())
        controller = report["data"]["controllers"][0]
        controller["binding"]["accessBackend"] = "GATT"
        controller["connectionState"]["backend"] = "GATT"
        controller["connectionState"]["transport"] = "BluetoothLE"

        self.validator.validate(report)

    def test_rejects_an_unknown_access_backend(self) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["controllers"][0]["binding"]["accessBackend"] = "coreBluetooth"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_an_unknown_name_for_each_value_kind(self) -> None:
        for path, name in self.unknown_names():
            with self.subTest(path=path, name=name):
                report = copy.deepcopy(load_fixture())
                *parents, key = path
                target: Any = report["data"]
                for step in parents:
                    target = target[step]
                target[key] = name

                with self.assertRaises(validate_schemas.ValidationError):
                    self.validator.validate(report)

    def unknown_names(self) -> list[tuple[list[str | int], str]]:
        controller: list[str | int] = ["controllers", 0]
        unbound: list[str | int] = ["unboundDevices", 0, "binding"]
        names: list[tuple[list[str | int], str]] = [
            (controller + ["binding", "accessBackend"], "ioHID"),
            (controller + ["binding", "accessBackend"], "ioUSBHost"),
            (controller + ["binding", "accessBackend"], "usbDriverKit"),
            (controller + ["binding", "accessBackend"], "coreBluetoothGATT"),
            (controller + ["binding", "outcome"], "bound"),
            (controller + ["binding", "rule"], "interfaceSignature"),
            (controller + ["binding", "matchedPredicates", 0], "interfaceSignature"),
            (unbound + ["interfaces", 0, "hostTransport"], "usb"),
            (controller + ["connectionState", "backend"], "ioUSBHost"),
            (controller + ["connectionState", "transport"], "usb"),
            (controller + ["connectionState", "transport"], "bluetoothClassic"),
            (controller + ["connectionState", "transport"], "bluetoothLE"),
            (
                controller + ["connectionState", "transport"],
                "proprietaryRadioReceiver",
            ),
            (controller + ["connectionState", "power", "charging"], "unknown"),
            (controller + ["inputHealth", "state"], "healthy"),
            (controller + ["inputHealth", "state"], "awaitingInput"),
            (controller + ["sessionState"], "active"),
            (unbound + ["outcome"], "unsupported"),
            (unbound + ["reason"], "ambiguousProtocolMatch"),
            (unbound + ["rejectedCandidates", 0, "reason"], "ambiguousProtocolMatch"),
            (["frameTimings", 0, "frames", 0, "stages", 0, "stage"], "read"),
            (
                ["frameTimings", 0, "frames", 0, "stages", 3, "stage"],
                "delivery-virtual-device",
            ),
            (
                ["frameTimings", 0, "frames", 0, "stages", 4, "stage"],
                "delivery-endpoint",
            ),
            (["system", "buildIdentity", "sourceState"], "clean"),
        ]
        return names

    def test_rejects_an_unknown_audit_source(self) -> None:
        report = self.system_words_report()
        report["data"]["systemGamepadAudit"]["source"] = "downloadedMobileAsset"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_the_enums_hold_only_the_current_names(self) -> None:
        schema = self.documents["report.schema.json"]
        enums: dict[str, list[str]] = {
            "/$defs/controllerInputHealth/properties/state/enum": [
                "awaitingInput",
                "waitingForNeutral",
            ],
            "/$defs/controllerInputHealth/properties/failureReason/enum": [
                "missingReports",
                "freshnessNotAdvancing",
            ],
            "/$defs/controllerConnectionState/properties/power/properties/charging/enum": [
                "notChargeable"
            ],
            "/$defs/hidGamepad/properties/serialKind/enum": ["ojdUserSpace", "none"],
            "/$defs/bindingResult/properties/rule/enum": ["hidDescriptor"],
            "/$defs/bindingResult/properties/matchedPredicates/items/enum": [
                "interruptEndpointPair",
                "hidDescriptorContract",
            ],
            "/$defs/bindingReason/enum": ["virtualProfileUnavailable"],
        }
        for pointer, names in enums.items():
            node: Any = schema
            for step in pointer.removeprefix("/").split("/"):
                node = node[step]
            for name in names:
                with self.subTest(pointer=pointer, name=name):
                    self.assertNotIn(name, node)
                    self.assertTrue(node)

    def test_rejects_a_top_level_catalog_record_id_on_an_unsupported_result(
        self,
    ) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["unboundDevices"][0]["binding"]["catalogRecordID"] = "045e-02d1"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_a_rejected_candidate_without_a_reason(self) -> None:
        report = copy.deepcopy(load_fixture())
        candidate = report["data"]["unboundDevices"][0]["binding"][
            "rejectedCandidates"
        ][0]
        del candidate["reason"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def system_words_report(self) -> dict[str, Any]:
        report = copy.deepcopy(load_fixture())
        report["data"]["systemGamepadAudit"] = {
            "source": "DownloadedMobileAsset",
            "bundleVersions": ["10.5.2"],
            "systemExactDeviceCount": 1,
            "skippedSystemDeviceCount": 0,
            "ojdRecordCount": 1,
            "catalogListedOJDRecordCount": 1,
            "records": [
                {
                    "vendorID": 1234,
                    "productID": 5678,
                    "name": "Test Controller",
                    "catalogListed": True,
                    "systemIdentifiers": ["test.controller"],
                    "transportConstraints": [],
                    "versionConstraints": [],
                }
            ],
            "warnings": [],
        }
        return report

    def test_accepts_the_neutral_system_words(self) -> None:
        report = self.system_words_report()
        self.assertEqual(report["data"]["system"]["osName"], "macOS")

        self.validator.validate(report)

    def test_rejects_a_report_without_os_name(self) -> None:
        report = self.system_words_report()
        del report["data"]["system"]["osName"]

        errors = [error.message for error in self.validator.iter_errors(report)]
        self.assertTrue(any("osName" in message for message in errors), errors)

    def test_has_a_system_record_definition(self) -> None:
        defs = cast(dict[str, Any], self.documents["report.schema.json"]["$defs"])

        self.assertIn("systemRecord", defs)


if __name__ == "__main__":
    unittest.main()
