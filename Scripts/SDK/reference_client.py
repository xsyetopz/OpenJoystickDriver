from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import socket
import subprocess
import sys
import threading
from collections.abc import Callable
from typing import Any, TextIO

API_VERSION = "openjoystickdriver/v1alpha3"
HEADER_ERRORS = ("E1009", "E1010", "E1011")
FRAMES: list[dict[str, Any]] = [{"buttons": ["South"], "holdMilliseconds": 100}, {}]


def proof(token: str, nonce: str) -> str:
    lines = ["OpenJoystickDriver endpoint hello 1", nonce, "", ""]
    message = "".join(line + "\n" for line in lines)
    key = hashlib.sha256(token.encode()).digest()
    return hmac.new(key, message.encode(), hashlib.sha256).hexdigest()


def hello(nonce: str, token: str, token_name: str, scope: str) -> dict[str, Any]:
    return {
        "apiVersion": API_VERSION,
        "kind": "Hello",
        "scopes": [scope],
        "tokenName": token_name,
        "proof": proof(token, nonce),
    }


def failure(message: dict[str, Any]) -> str:
    text = f"{message.get('code')}: {message.get('message')}"
    supported = (message.get("details") or {}).get("supportedAPIVersions")
    if message.get("code") in HEADER_ERRORS and supported:
        text += f" Supported apiVersion values: {', '.join(supported)}."
    return text


def parse_line(line: str) -> dict[str, Any]:
    try:
        message = json.loads(line)
    except ValueError as error:
        sys.exit(f"The endpoint sent a line that is not JSON: {error}")
    if not isinstance(message, dict):
        sys.exit("The endpoint sent a line that is not a JSON object.")
    header = message.get("object") if "kind" not in message else message
    if not isinstance(header, dict):
        sys.exit("The endpoint sent a watch line without an object.")
    if header.get("kind") != "Status" and header.get("apiVersion") != API_VERSION:
        sys.exit(
            f"The endpoint sent apiVersion {header.get('apiVersion')!r}, "
            f"and this client speaks only {API_VERSION}."
        )
    return message


def send(endpoint: socket.socket, message: dict[str, Any]) -> None:
    endpoint.sendall((json.dumps(message) + "\n").encode())


def socket_path(arguments: argparse.Namespace) -> str:
    if arguments.socket:
        return arguments.socket
    status = json.loads(subprocess.check_output(["ojd", "--json", "access", "status"]))
    return status["socketPath"]


def connect(
    endpoint: socket.socket, reader: TextIO, arguments: argparse.Namespace, scope: str
) -> Callable[[], dict[str, Any]]:

    def receive() -> dict[str, Any]:
        line = reader.readline()
        if not line:
            sys.exit("The endpoint closed the connection.")
        message = parse_line(line)
        if message.get("kind") == "Status":
            sys.exit(failure(message))
        return message

    nonce = receive()["nonce"]
    send(endpoint, hello(nonce, arguments.token, arguments.token_name, scope))
    receive()  # Welcome
    return receive


def watch(arguments: argparse.Namespace) -> None:
    with socket.socket(socket.AF_UNIX) as endpoint:
        endpoint.settimeout(arguments.timeout)
        endpoint.connect(socket_path(arguments))
        reader = endpoint.makefile("r")
        receive = connect(endpoint, reader, arguments, "Read")
        subscription = {
            "apiVersion": API_VERSION,
            "kind": "Subscription",
            "stream": "Controllers",
        }
        send(endpoint, subscription)
        try:
            for _ in range(arguments.count):
                print(json.dumps(receive()))
        except TimeoutError:
            sys.exit(f"No watch line arrived within {arguments.timeout:g} seconds.")


def feed(arguments: argparse.Namespace) -> None:
    with socket.socket(socket.AF_UNIX) as endpoint:
        endpoint.connect(socket_path(arguments))
        reader = endpoint.makefile("r")
        receive = connect(endpoint, reader, arguments, "Control")
        finished = threading.Event()
        reasons: list[str] = []

        def print_lines() -> None:
            try:
                for line in reader:
                    message = parse_line(line)
                    if message.get("kind") == "Status":
                        reasons.append(failure(message))
                        break
                    if message.get("kind") == "Drained":
                        break
                    print(line, end="")
                else:
                    reasons.append("The endpoint closed the connection.")
            except SystemExit as error:
                reasons.append(str(error.code))
            except OSError as error:
                reasons.append(f"The connection to the endpoint failed: {error}")
            finished.set()

        send(
            endpoint,
            {"apiVersion": API_VERSION, "kind": "FeedRequest", "as": "Generic"},
        )
        receive()  # FeedSession
        threading.Thread(target=print_lines, daemon=True).start()
        try:
            for frame in FRAMES:
                send(endpoint, {"apiVersion": API_VERSION, "kind": "Frame", **frame})
            send(endpoint, {"apiVersion": API_VERSION, "kind": "Drain"})
        except OSError:
            pass  # The reader reports why the endpoint closed the connection.
        finished.wait()
        if reasons:
            sys.exit(reasons[0])
        endpoint.shutdown(socket.SHUT_RDWR)  # The reader thread keeps the socket open.


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--socket", help="the endpoint socket; default: from `ojd access status`"
    )
    parser.add_argument(
        "--token-name", default="driver", help="the name given to `--token`"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    watcher = commands.add_parser("watch", help="subscribe to the Controllers stream")
    watcher.add_argument("--count", type=int, default=1, help="watch lines to print")
    watcher.add_argument(
        "--timeout",
        type=float,
        help="seconds to wait for the endpoint before the run fails; default: wait",
    )
    watcher.set_defaults(run=watch)
    commands.add_parser("feed", help="drive a virtual gamepad").set_defaults(run=feed)
    arguments = parser.parse_args(argv)
    arguments.token = os.environ.get("OJD_TOKEN")
    if not arguments.token:
        sys.exit("Set OJD_TOKEN to the token that `ojd access grant --token` printed.")
    try:
        arguments.run(arguments)
    except OSError as error:
        sys.exit(f"The connection to the endpoint failed: {error}")


if __name__ == "__main__":
    main()
