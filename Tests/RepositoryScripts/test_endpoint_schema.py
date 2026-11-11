from __future__ import annotations

import unittest
from typing import Any

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha3"
NONCE = "A" * 43


def line(kind: str, **fields: Any) -> dict[str, Any]:
    return {"apiVersion": VERSION, "kind": kind, **fields}


def failure(code: str, **fields: Any) -> dict[str, Any]:
    return line("Status", status="Failure", code=code, message="text", **fields)


PROFILE = {
    "id": "7B6B3C5E-9A4D-4A6E-8C55-1B2D3E4F5A6B",
    "name": "Rally",
    "model": "054C:0CE6",
    "isActive": True,
}

DETAILS = {"details": {"supportedAPIVersions": [VERSION]}}


class EndpointSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.validator = validate_schemas.Draft202012Validator(
            documents["endpoint.schema.json"],
            registry=validate_schemas.schema_registry(documents),
            format_checker=validate_schemas.FormatChecker(),
        )

    def valid(self, message: dict[str, Any]) -> bool:
        return self.validator.is_valid(message)

    def test_accepts_every_message_of_the_protocol(self) -> None:
        messages = [
            line("Challenge", nonce=NONCE),
            line("Hello", scopes=["Read", "Control"]),
            line("Welcome", version="0.6.0", scopes=["Read"]),
            line("Subscription", stream="Controllers", output=True),
            line("FeedRequest", **{"as": "Generic"}),
            line("FeedSession", **{"as": "SDLCompatible"}),
            line("Frame", buttons=["South"], axes={"LeftStickX": 0.5}),
            line("KeepAlive"),
            line("Drain"),
            line("Drained"),
            line("ProfileRequest", action="Activate", profile="Rally"),
            line("ProfileRequest", action="Set", profile="Rally", key="name", value="X"),
            line("ProfileRequest", action="Set", profile="Rally", key="a.b", value=None),
            line("ProfileResult", profile=PROFILE),
            failure("E1001"),
            failure("E1003"),
            failure("E2012"),
            failure("E1009", **DETAILS),
            failure("E1010", **DETAILS),
            failure("E1011", **DETAILS),
        ]
        for message in messages:
            self.assertTrue(self.valid(message), message)

    def test_a_keep_alive_has_no_member_besides_the_header(self) -> None:
        self.assertTrue(self.valid(line("KeepAlive")))
        self.assertFalse(self.valid(line("KeepAlive", buttons=["notAName"])))
        self.assertFalse(self.valid({"kind": "KeepAlive"}))

    def test_a_drain_and_a_drained_have_no_member_besides_the_header(self) -> None:
        for kind in ("Drain", "Drained"):
            self.assertTrue(self.valid(line(kind)), kind)
            self.assertFalse(self.valid(line(kind, buttons=["South"])), kind)
            self.assertFalse(self.valid({"kind": kind}), kind)

    def test_the_header_codes_need_the_supported_versions_and_no_other_code_has_them(
        self,
    ) -> None:
        for code in ("E1009", "E1010", "E1011"):
            self.assertFalse(self.valid(failure(code)), code)
        empty = {"details": {"supportedAPIVersions": []}}
        self.assertFalse(self.valid(failure("E1009", **empty)))
        for code in ("E1001", "E1002", "E1003", "E1008"):
            self.assertFalse(self.valid(failure(code, **DETAILS)), code)

    def test_a_profile_request_is_refused_when_it_is_malformed(self) -> None:
        refused = [
            line("ProfileRequest", action="Jump", profile="Rally"),
            line("ProfileRequest", action="set", profile="Rally"),
            line("ProfileRequest", action="Set", profile="Rally", key="name"),
            line("ProfileRequest", action="Set", profile="Rally", value="X"),
            line("ProfileRequest", action="Activate", profile="Rally", key="name"),
            line("ProfileRequest", action="Activate", profile=""),
            line("ProfileRequest", action="Activate"),
            line("ProfileResult", profile={**PROFILE, "extra": 1}),
            line("ProfileResult", profile={**PROFILE, "id": "not-a-uuid"}),
        ]
        for message in refused:
            self.assertFalse(self.valid(message), message)

    def test_a_request_failure_carries_a_code_outside_the_endpoint_codes(self) -> None:
        self.assertFalse(self.valid(failure("E2")))
        self.assertFalse(self.valid(failure("X2012")))
        self.assertFalse(self.valid(failure("E2012", **DETAILS)))

    def test_the_earlier_spellings_are_refused(self) -> None:
        self.assertFalse(self.valid(line("Hello", scopes=["read"])))
        self.assertFalse(
            self.valid(line("Welcome", version="0.6.0", scopes=["control"]))
        )
        self.assertFalse(self.valid(line("Subscription", stream="controllers")))

    def test_an_unknown_persona_id_is_refused(self) -> None:
        for name in ("NotAPersona", "SdlCompatible", "quokka", "marmalade"):
            self.assertFalse(self.valid(line("FeedRequest", **{"as": name})), name)
            self.assertFalse(self.valid(line("FeedSession", **{"as": name})), name)

    def test_an_unsupported_api_version_is_not_accepted(self) -> None:
        unsupported = "unsupported.example/v9"
        self.assertFalse(
            self.valid({"apiVersion": unsupported, "kind": "Hello", "scopes": ["Read"]})
        )
        self.assertFalse(
            self.valid({**failure("E1009", **DETAILS), "apiVersion": unsupported})
        )

    def test_a_line_needs_both_header_members(self) -> None:
        hello = line("Hello", scopes=["Read"])
        self.assertTrue(self.valid(hello))
        for member in ("apiVersion", "kind"):
            self.assertFalse(
                self.valid(
                    {key: value for key, value in hello.items() if key != member}
                )
            )


if __name__ == "__main__":
    unittest.main()
