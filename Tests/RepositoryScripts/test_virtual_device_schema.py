"""The VirtualDevice kind, refused for the same reasons `VirtualDeviceTests` refuses it in Swift."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

ROOT = Path(__file__).resolve().parents[2]
BUNDLED = ROOT / "Resources" / "VirtualDevices"
HEADER = {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "VirtualDevice"}


def load(name: str) -> dict[str, Any]:
    return json.loads((BUNDLED / name).read_text(encoding="utf-8"))


class VirtualDeviceSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        cls.validator = validate_schemas.Draft202012Validator(
            documents["virtual-device.schema.json"], registry=registry
        )

    def refuses(self, document: dict[str, Any]) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(document)

    def test_the_bundled_definitions_are_accepted(self) -> None:
        for name in (
            "virtual-device.generic.json",
            "virtual-device.sdl-compatible.json",
        ):
            with self.subTest(record=name):
                self.validator.validate(load(name))

    def test_a_match_record_selects_a_persona_without_a_layout(self) -> None:
        self.validator.validate(
            {
                **HEADER,
                "persona": "SDLCompatible",
                "match": {"vendorID": 1, "productID": 2},
            }
        )

    def test_a_bad_header_is_refused(self) -> None:
        for document in (
            {"apiVersion": "openjoystickdriver/v2", "kind": "VirtualDevice"},
            {"kind": "VirtualDevice"},
            {"apiVersion": HEADER["apiVersion"], "kind": "Persona"},
            {"apiVersion": HEADER["apiVersion"]},
        ):
            with self.subTest(header=document):
                self.refuses({**document, "persona": "Generic"})

    def test_an_unknown_persona_is_refused(self) -> None:
        for persona in ("NotAPersona", "SdlCompatible", "quokka", ""):
            with self.subTest(persona=persona):
                self.refuses(
                    {**load("virtual-device.generic.json"), "persona": persona}
                )

    def test_a_match_record_holds_no_layout_or_transport(self) -> None:
        match = {"vendorID": 1, "productID": 2}
        self.refuses(
            {
                **HEADER,
                "persona": "Generic",
                "match": match,
                "layout": "OJDGenericGamepad",
            }
        )
        self.refuses(
            {**HEADER, "persona": "Generic", "match": match, "transport": "USB"}
        )
        self.refuses(
            {
                **HEADER,
                "persona": "Generic",
                "match": match,
                "worksWithDefaultSDLHints": True,
            }
        )

    def test_a_match_needs_valid_ids_and_unit(self) -> None:
        for match in (
            {"vendorID": 1},
            {"productID": 2},
            {"vendorID": 0, "productID": 2},
            {"vendorID": 1, "productID": 65536},
            {"vendorID": 1, "productID": 2, "unit": "not-a-unit"},
            {"vendorID": 1, "productID": 2, "extra": True},
        ):
            with self.subTest(match=match):
                self.refuses({**HEADER, "persona": "Generic", "match": match})

    def test_a_definition_holds_layout_transport_hints_labels_and_identity_with_version(
        self,
    ) -> None:
        for member in (
            "layout",
            "transport",
            "worksWithDefaultSDLHints",
            "labels",
            "identity",
        ):
            with self.subTest(missing=member):
                document = load("virtual-device.generic.json")
                del document[member]
                self.refuses(document)
        document = load("virtual-device.generic.json")
        del document["identity"]["version"]
        self.refuses(document)

    def test_a_definition_refuses_unknown_members_and_values(self) -> None:
        for member, value in (
            ("layout", "other"),
            ("layout", "ojd-generic-gamepad"),
            ("layout", "xbox-one-s-bluetooth"),
            ("labels", "xbox"),
            ("labels", "generic"),
            ("transport", "Serial"),
            ("labels", "playstation"),
            ("worksWithDefaultSDLHints", "yes"),
            ("extra", 1),
        ):
            with self.subTest(member=member):
                document = copy.deepcopy(load("virtual-device.generic.json"))
                document[member] = value
                self.refuses(document)


if __name__ == "__main__":
    unittest.main()
