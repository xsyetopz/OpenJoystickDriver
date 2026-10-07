from __future__ import annotations

import io
import json
import re
import runpy
import socket
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Quality import validate_schemas

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "wiki" / "Automating-OpenJoystickDriver.md"
HEADING = "### Drive a Virtual Gamepad Through the Endpoint"
VECTOR = Path(__file__).resolve().parent / "fixtures" / "endpoint_hello_proof.json"


def client_source() -> str:
    """The first Python block after HEADING in the wiki page."""
    text = PAGE.read_text(encoding="utf-8")
    section = text[text.index(HEADING) :]
    match = re.search(r"^```python\n(.*?)^```$", section, re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"{PAGE.name} has no Python block after {HEADING}")
    return match.group(1)


class EndpointReferenceClientTests(unittest.TestCase):
    def setUp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "driver.py"
            path.write_text(client_source(), encoding="utf-8")
            self.client = runpy.run_path(str(path), run_name="reference_client")
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        endpoint = documents["endpoint.schema.json"]["$id"]

        def validator(name: str) -> validate_schemas.Draft202012Validator:
            return validate_schemas.Draft202012Validator(
                {"$ref": f"{endpoint}#/$defs/{name}"}, registry=registry
            )

        self.client_lines = validator("clientLine")
        self.service_lines = validator("serviceLine")

    def envelope(self, kind: str, **fields: Any) -> dict[str, Any]:
        return {"apiVersion": self.client["API_VERSION"], "kind": kind, **fields}

    def feed_request(self) -> dict[str, Any]:
        return self.envelope("FeedRequest", **{"as": "hid-generic"})

    def frame_lines(self) -> list[dict[str, Any]]:
        return [self.envelope("Frame", **frame) for frame in self.client["FRAMES"]]

    def test_proof_matches_the_vector_the_swift_tests_use(self) -> None:
        vector = json.loads(VECTOR.read_text(encoding="utf-8"))
        self.assertEqual((vector["origin"], vector["port"]), ("", ""))
        self.assertEqual(
            self.client["proof"](vector["token"], vector["nonce"]), vector["proof"]
        )

    def test_client_lines_match_the_schema(self) -> None:
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        lines = [
            self.client["hello"](nonce),
            self.feed_request(),
            *self.frame_lines(),
        ]
        for line in lines:
            with self.subTest(line=line):
                self.client_lines.validate(line)

    def test_schema_rejects_a_frame_with_a_repeated_button(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate(
                self.envelope("Frame", buttons=["south", "south"])
            )

    def test_schema_rejects_a_frame_without_the_envelope(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate({"buttons": ["south"]})

    def test_service_lines_match_the_schema(self) -> None:
        lines = [
            self.envelope("FeedSession", **{"as": "hid-generic"}),
            {
                "apiVersion": self.client["API_VERSION"],
                "kind": "RumbleCommand",
                "type": "setRumble",
                "intensities": {
                    "leftMain": 65535,
                    "rightMain": 0,
                    "leftTrigger": 0,
                    "rightTrigger": 0,
                    "leftHaptic": 0,
                    "rightHaptic": 0,
                },
                "durationMilliseconds": 200,
            },
            self.envelope("RumbleCommand", type="stopRumble"),
            self.envelope("Status", status="Failure", code="E1008", message="Full."),
            self.envelope(
                "Status",
                status="Failure",
                code="E1003",
                message="Unsupported.",
                details={"supportedAPIVersions": [self.client["API_VERSION"]]},
            ),
            {
                "type": "ADDED",
                "object": self.envelope(
                    "Controller",
                    id="pad-1",
                    name="Test Pad",
                    vendorID=1118,
                    productID=654,
                    connection="usb",
                    hasSerialNumber=False,
                    protocol="xbox.xbox360",
                    session="active",
                ),
            },
        ]
        for line in lines:
            with self.subTest(line=line):
                self.service_lines.validate(line)

    def test_client_runs_against_a_fake_endpoint(self) -> None:
        """A fake endpoint, not the service: it checks the client's order of lines."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        rumble = self.envelope("RumbleCommand", type="stopRumble")
        received: list[dict[str, Any]] = []
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)

                def serve() -> None:
                    connection, _ = listener.accept()
                    with connection, connection.makefile("rw") as lines:

                        def send(message: dict[str, Any]) -> None:
                            lines.write(json.dumps(message) + "\n")
                            lines.flush()

                        send(self.envelope("Challenge", nonce=nonce))
                        received.append(json.loads(lines.readline()))
                        send(
                            self.envelope("Welcome", version="test", scopes=["control"])
                        )
                        received.append(json.loads(lines.readline()))
                        send(self.envelope("FeedSession", **{"as": "hid-generic"}))
                        send(rumble)
                        received.extend(json.loads(line) for line in lines)

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                status = json.dumps({"socketPath": path})
                output = io.StringIO()
                with (
                    patch("subprocess.check_output", return_value=status),
                    redirect_stdout(output),
                ):
                    self.client["main"]()
                server.join(timeout=5)

        self.assertFalse(server.is_alive())
        self.assertEqual(received[0], self.client["hello"](nonce))
        self.assertEqual(
            received[1:],
            [self.feed_request(), *self.frame_lines()],
        )
        self.assertEqual(json.loads(output.getvalue()), rumble)

    def run_until_feeding(self, after_feeding: Any) -> SystemExit:
        """Runs the client against a fake endpoint that calls `after_feeding(send)` once the
        client sent `feed`; returns the client's exit."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)

                def serve() -> None:
                    connection, _ = listener.accept()
                    with connection, connection.makefile("rw") as lines:

                        def send(message: dict[str, Any]) -> None:
                            lines.write(json.dumps(message) + "\n")
                            lines.flush()

                        send(self.envelope("Challenge", nonce=nonce))
                        lines.readline()
                        send(self.envelope("Welcome", version="test", scopes=[]))
                        lines.readline()
                        send(self.envelope("FeedSession", **{"as": "hid-generic"}))
                        after_feeding(send)

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                status = json.dumps({"socketPath": path})
                with (
                    patch("subprocess.check_output", return_value=status),
                    redirect_stdout(io.StringIO()),
                    self.assertRaises(SystemExit) as exit_info,
                ):
                    self.client["main"]()
                server.join(timeout=5)
        return exit_info.exception

    def test_client_exits_with_the_error_line_the_endpoint_sends(self) -> None:
        error = self.envelope(
            "Status",
            status="Failure",
            code="E1009",
            message="The virtual gamepad closed.",
        )
        exit_info = self.run_until_feeding(lambda send: send(error))

        self.assertIn("E1009", str(exit_info.code))
        self.assertNotIn(exit_info.code, (0, None))

    def test_client_exits_when_the_endpoint_closes_before_the_release_has_played(
        self,
    ) -> None:
        exit_info = self.run_until_feeding(lambda send: None)

        self.assertIn("closed the connection", str(exit_info.code))

    def test_client_stays_connected_until_the_last_frame_has_played(self) -> None:
        # The 100 ms press, then the release for the 8 ms minimum.
        self.assertAlmostEqual(
            self.client["play_seconds"](self.client["FRAMES"]), 0.108
        )


if __name__ == "__main__":
    unittest.main()
