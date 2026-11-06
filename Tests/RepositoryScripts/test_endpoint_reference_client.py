from __future__ import annotations

import io
import json
import os
import queue
import socket
import struct
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Quality import repository_tool, validate_schemas
from Scripts.SDK import reference_client

ROOT = Path(__file__).resolve().parents[2]
VECTOR = Path(__file__).resolve().parent / "fixtures" / "endpoint_hello_proof.json"


class EndpointReferenceClientTests(unittest.TestCase):
    def setUp(self) -> None:
        vector = json.loads(VECTOR.read_text(encoding="utf-8"))
        self.client = {
            "API_VERSION": reference_client.API_VERSION,
            "FRAMES": reference_client.FRAMES,
            "proof": reference_client.proof,
            "hello": lambda nonce: reference_client.hello(
                nonce, vector["token"], "driver", "Control"
            ),
        }
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        endpoint = documents["endpoint.schema.json"]["$id"]

        def validator(name: str) -> validate_schemas.Draft202012Validator:
            return validate_schemas.Draft202012Validator(
                {"$ref": f"{endpoint}#/$defs/{name}"}, registry=registry
            )

        self.client_lines = validator("clientLine")
        self.service_lines = validator("serviceLine")

    def test_the_sample_names_the_swift_api_version_and_header_codes(self) -> None:
        # The sample client is a standalone file for readers of the SDK, so it states these two
        # facts itself; this test is what keeps them equal to Swift and the error catalog.
        self.assertEqual(reference_client.API_VERSION, repository_tool.api_version())
        catalog = json.loads(
            (ROOT / "Resources/ErrorCodes.json").read_text(encoding="utf-8")
        )["codes"]
        header_codes = {"unsupportedEndpointVersion", "unexpectedKind", "missingHeader"}
        self.assertEqual(
            set(reference_client.HEADER_ERRORS),
            {entry["code"] for entry in catalog if entry["name"] in header_codes},
        )

    def client_environment(self) -> Any:
        token = json.loads(VECTOR.read_text(encoding="utf-8"))["token"]
        return patch.dict(os.environ, {"OJD_TOKEN": token})

    def envelope(self, kind: str, **fields: Any) -> dict[str, Any]:
        return {"apiVersion": self.client["API_VERSION"], "kind": kind, **fields}

    def feed_request(self) -> dict[str, Any]:
        return self.envelope("FeedRequest", **{"as": "Generic"})

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
            self.envelope("Drain"),
        ]
        for line in lines:
            with self.subTest(line=line):
                self.client_lines.validate(line)

    def test_schema_rejects_a_frame_with_a_repeated_button(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate(
                self.envelope("Frame", buttons=["South", "South"])
            )

    def test_schema_rejects_a_frame_without_the_envelope(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate({"buttons": ["South"]})

    def test_service_lines_match_the_schema(self) -> None:
        lines = [
            self.envelope("FeedSession", **{"as": "Generic"}),
            self.envelope("Drained"),
            {
                "apiVersion": self.client["API_VERSION"],
                "kind": "RumbleCommand",
                "type": "SetRumble",
                "intensities": {
                    "lowFrequency": 65535,
                    "highFrequency": 0,
                    "leftTrigger": 0,
                    "rightTrigger": 0,
                    "leftHaptic": 0,
                    "rightHaptic": 0,
                },
                "durationMilliseconds": 200,
            },
            self.envelope("RumbleCommand", type="StopRumble"),
            self.envelope("Status", status="Failure", code="E1007", message="Full."),
            self.envelope(
                "Status",
                status="Failure",
                code="E1009",
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
                    ownedByAnotherClient=False,
                    alsoListedBySystem=False,
                    protocol="XboxXUSB:Wired",
                    session="Active",
                    waitsForGuidePress=False,
                ),
            },
        ]
        for line in lines:
            with self.subTest(line=line):
                self.service_lines.validate(line)

    def test_client_runs_against_a_fake_endpoint(self) -> None:
        """A fake endpoint, not the service: it checks the client's order of lines."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        rumble = self.envelope("RumbleCommand", type="StopRumble")
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
                            self.envelope("Welcome", version="test", scopes=["Control"])
                        )
                        received.append(json.loads(lines.readline()))
                        send(self.envelope("FeedSession", **{"as": "Generic"}))
                        send(rumble)
                        for line in lines:
                            received.append(json.loads(line))
                            if received[-1]["kind"] == "Drain":
                                send(self.envelope("Drained"))

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                output = io.StringIO()
                with self.client_environment(), redirect_stdout(output):
                    reference_client.main(["--socket", path, "feed"])
                server.join(timeout=5)

        self.assertFalse(server.is_alive())
        self.assertEqual(received[0], self.client["hello"](nonce))
        self.assertEqual(
            received[1:],
            [self.feed_request(), *self.frame_lines(), self.envelope("Drain")],
        )
        self.assertEqual(json.loads(output.getvalue()), rumble)

    def test_client_closes_only_after_a_slow_endpoint_has_played_every_frame(
        self,
    ) -> None:
        """The fake endpoint plays one frame at a time, slowly, and drops the frames that
        wait when the client closes the connection."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        waiting: queue.Queue[dict[str, Any]] = queue.Queue()
        played: list[dict[str, Any]] = []
        played_at_close: list[list[dict[str, Any]]] = []
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)

                def play() -> None:
                    while True:
                        frame = waiting.get()
                        time.sleep(0.15)
                        played.append(frame)
                        waiting.task_done()

                threading.Thread(target=play, daemon=True).start()

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
                        send(self.envelope("FeedSession", **{"as": "Generic"}))
                        for line in lines:
                            message = json.loads(line)
                            if message["kind"] == "Frame":
                                waiting.put(message)
                            elif message["kind"] == "Drain":
                                waiting.join()
                                send(self.envelope("Drained"))
                        played_at_close.append(list(played))

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                with self.client_environment(), redirect_stdout(io.StringIO()):
                    reference_client.main(["--socket", path, "feed"])
                server.join(timeout=5)

        self.assertEqual(played_at_close, [self.frame_lines()])

    def run_until_feeding(self, after_feeding: Any) -> SystemExit:
        """Runs the client against a fake endpoint that calls `after_feeding(send, reset)` once
        the client sent `feed`; returns the client's exit."""
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
                        send(self.envelope("FeedSession", **{"as": "Generic"}))

                        def reset() -> None:
                            # A zero linger makes close() send a reset, not an end of file.
                            connection.setsockopt(
                                socket.SOL_SOCKET,
                                socket.SO_LINGER,
                                struct.pack("ii", 1, 0),
                            )
                            connection.close()

                        after_feeding(send, reset)

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                with (
                    self.client_environment(),
                    redirect_stdout(io.StringIO()),
                    self.assertRaises(SystemExit) as exit_info,
                ):
                    reference_client.main(["--socket", path, "feed"])
                server.join(timeout=5)
        return exit_info.exception

    def test_client_exits_with_the_error_line_the_endpoint_sends(self) -> None:
        error = self.envelope(
            "Status",
            status="Failure",
            code="E1008",
            message="The virtual gamepad closed.",
        )
        exit_info = self.run_until_feeding(lambda send, _reset: send(error))

        self.assertIn("E1008", str(exit_info.code))
        self.assertNotIn(exit_info.code, (0, None))

    def test_client_exits_when_the_endpoint_closes_before_the_release_has_played(
        self,
    ) -> None:
        exit_info = self.run_until_feeding(lambda _send, _reset: None)

        self.assertIn("closed the connection", str(exit_info.code))

    def test_client_exits_when_the_connection_is_reset_mid_stream(self) -> None:
        exit_info = self.run_until_feeding(lambda _send, reset: reset())

        self.assertNotIn(exit_info.code, (0, None))
        self.assertIsInstance(exit_info.code, str)

    def test_client_exits_cleanly_when_the_endpoint_refuses_the_connection(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "missing.sock")
            for command in (["feed"], ["watch"]):
                with (
                    self.subTest(command=command),
                    self.client_environment(),
                    self.assertRaises(SystemExit) as exit_info,
                ):
                    reference_client.main(["--socket", path, *command])
                self.assertIn("failed", str(exit_info.exception.code))

    def test_watch_times_out_when_no_line_arrives(self) -> None:
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)
                done = threading.Event()

                def serve() -> None:
                    connection, _ = listener.accept()
                    with connection, connection.makefile("rw") as lines:
                        lines.write(
                            json.dumps(self.envelope("Challenge", nonce=nonce)) + "\n"
                        )
                        lines.flush()
                        lines.readline()
                        welcome = self.envelope("Welcome", version="test", scopes=[])
                        lines.write(json.dumps(welcome) + "\n")
                        lines.flush()
                        lines.readline()
                        done.wait(5)  # No controller: no watch line follows.

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                with (
                    self.client_environment(),
                    redirect_stdout(io.StringIO()),
                    self.assertRaises(SystemExit) as exit_info,
                ):
                    reference_client.main(
                        ["--socket", path, "watch", "--timeout", "0.3"]
                    )
                done.set()
                server.join(timeout=5)

        self.assertIn("within 0.3 seconds", str(exit_info.exception.code))

    def test_client_reports_the_supported_versions_on_a_header_error(self) -> None:
        for code in ("E1009", "E1010", "E1011"):
            error = self.envelope(
                "Status",
                status="Failure",
                code=code,
                message="Refused.",
                details={"supportedAPIVersions": ["openjoystickdriver/v1alpha2"]},
            )
            with self.subTest(code=code):
                exit_info = self.run_until_feeding(
                    lambda send, _reset, error=error: send(error)
                )

                self.assertIn(code, str(exit_info.code))
                self.assertIn("openjoystickdriver/v1alpha2", str(exit_info.code))
                self.assertIn("Supported apiVersion values", str(exit_info.code))

    def test_client_refuses_a_line_with_another_api_version(self) -> None:
        line = {"apiVersion": "unsupported.example/v9", "kind": "Challenge"}
        with self.assertRaises(SystemExit) as exit_info:
            reference_client.parse_line(json.dumps(line))

        self.assertIn("unsupported.example/v9", str(exit_info.exception.code))
        self.assertIn(reference_client.API_VERSION, str(exit_info.exception.code))

    def test_client_checks_the_header_of_a_watch_lines_object(self) -> None:
        controller = {"id": "pad-1", "name": "Test Pad"}
        watch = {"type": "ADDED", "object": self.envelope("Controller", **controller)}
        self.assertEqual(reference_client.parse_line(json.dumps(watch)), watch)

        foreign = {
            "type": "ADDED",
            "object": {"apiVersion": "other/v1", "kind": "Controller"},
        }
        with self.assertRaises(SystemExit) as exit_info:
            reference_client.parse_line(json.dumps(foreign))
        self.assertIn("other/v1", str(exit_info.exception.code))

    def test_client_refuses_to_run_without_a_token(self) -> None:
        with (
            patch.dict(os.environ, {}, clear=True),
            self.assertRaises(SystemExit) as exit_info,
        ):
            reference_client.main(["--socket", "/tmp/none.sock", "watch"])
        self.assertIn("OJD_TOKEN", str(exit_info.exception.code))

    def test_client_has_no_play_time_estimate(self) -> None:
        self.assertFalse(hasattr(reference_client, "play_seconds"))
        self.assertFalse(hasattr(reference_client, "MARGIN_SECONDS"))


if __name__ == "__main__":
    unittest.main()
