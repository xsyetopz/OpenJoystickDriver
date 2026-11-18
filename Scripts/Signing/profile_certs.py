from __future__ import annotations

import hashlib
import re
import subprocess


def certificate_sha1_list(profile: dict) -> list[str]:
    certificates = profile.get("DeveloperCertificates", [])
    for index, certificate in enumerate(certificates):
        if not isinstance(certificate, (bytes, bytearray)):
            raise TypeError(
                f"DeveloperCertificates[{index}] is {type(certificate).__name__}, not data"
            )
    return [
        hashlib.sha1(bytes(certificate), usedforsecurity=False).hexdigest()
        for certificate in certificates
    ]


def keychain_identities(prefix: str) -> dict[str, str]:
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"`security find-identity` failed ({result.returncode}): "
            f"{result.stderr.strip()}"
        )
    pattern = re.compile(
        rf'^\s*\d+\)\s+([0-9A-Fa-f]{{40}})\s+"({re.escape(prefix)}:[^"]*)"'
    )
    found: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if match := pattern.search(line):
            found[match.group(1).lower()] = match.group(2)
    return found


def shared_identity_sha1s(
    profile_sha1_lists: list[list[str]], identities: dict[str, str]
) -> list[str]:
    return sorted(
        sha1
        for sha1 in identities
        if all(sha1 in embedded for embedded in profile_sha1_lists)
    )
