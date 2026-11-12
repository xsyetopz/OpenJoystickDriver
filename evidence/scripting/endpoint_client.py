"""Shared helper of the 6.17 scripts: connect to the endpoint socket with a token and print a transcript.

Reads the token from the file named by OJD_TOKEN_FILE and its name from OJD_TOKEN_NAME. The transcript
prints each line sent (`->`) and received (`<-`); the proof is shown as [REDACTED]. The token is never printed.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import socket
import subprocess
from typing import Any

API = "openjoystickdriver/v1alpha3"
APP = "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"


def ojd(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Runs the installed CLI as `ojd` and prints the command and its exit status."""
    result = subprocess.run(
        ["ojd", "--no-input", *arguments],
        executable=APP,
        capture_output=True,
        text=True,
        check=False,
    )
    print(f"$ ojd {' '.join(arguments)}  -> exit {result.returncode}")
    for line in (result.stdout + result.stderr).strip().splitlines():
        print(f"  {line}")
    return result


def socket_path() -> str:
    status = subprocess.run(
        ["ojd", "--json", "access", "status"], executable=APP, capture_output=True, text=True, check=True
    )
    return json.loads(status.stdout)["socketPath"]


class Client:
    """One endpoint connection that has finished the handshake."""

    def __init__(self, scopes: list[str]) -> None:
        self.endpoint = socket.socket(socket.AF_UNIX)
        self.endpoint.settimeout(8)
        self.endpoint.connect(socket_path())
        self.reader = self.endpoint.makefile("r")
        nonce = json.loads(self.reader.readline())["nonce"]
        with open(os.environ["OJD_TOKEN_FILE"]) as file:
            token = file.read().strip()
        name = os.environ["OJD_TOKEN_NAME"]
        text = "".join(line + "\n" for line in ["OpenJoystickDriver endpoint hello 1", nonce, "", ""])
        key = hashlib.sha256(token.encode()).digest()
        proof = hmac.new(key, text.encode(), hashlib.sha256).hexdigest()
        hello = {"kind": "Hello", "scopes": scopes, "tokenName": name}
        self.send({**hello, "proof": proof}, shown={**hello, "proof": "[REDACTED]"})
        self.receive()

    def send(self, message: dict[str, Any], shown: dict[str, Any] | None = None) -> None:
        print("->", json.dumps({"apiVersion": API, **(shown or message)}))
        self.endpoint.sendall((json.dumps({"apiVersion": API, **message}) + "\n").encode())

    def receive(self, timeout: float = 8) -> dict[str, Any] | None:
        self.endpoint.settimeout(timeout)
        try:
            line = self.reader.readline()
        except TimeoutError:
            print("<- (no line within", timeout, "seconds)")
            return None
        if not line:
            print("<- (connection closed)")
            return None
        print("<-", line.strip())
        return json.loads(line)

    def ask(self, message: dict[str, Any]) -> dict[str, Any] | None:
        self.send(message)
        return self.receive()

    def close(self) -> None:
        self.endpoint.close()
