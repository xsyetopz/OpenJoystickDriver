"""Provisioning profile and certificate facts for the `just signing-*` recipes.

Run as a script: `profile_certs.py audit|cert-info|profile-info|extract-certs ...`. The output
names a certificate by shortened hashes unless `--full` is given, so it can be pasted into an
issue without the full identifiers.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def decoded_profile(path: str) -> dict | None:
    """Returns the property list a signed profile holds, or None when it does not decode."""
    for command in (
        ["security", "cms", "-D", "-i", path],
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
    ):
        result = subprocess.run(command, capture_output=True, check=False)
        if result.returncode == 0 and b"<?xml" in result.stdout:
            raw = result.stdout[result.stdout.index(b"<?xml") :]
            try:
                return plistlib.loads(raw)
            except (ValueError, plistlib.InvalidFileException):
                return None
    return None


def embedded_certificates(profile: dict) -> list[bytes]:
    return [
        bytes(certificate)
        for certificate in profile.get("DeveloperCertificates") or []
        if isinstance(certificate, (bytes, bytearray))
    ]


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


def certificate_facts(der: bytes) -> dict[str, str]:
    """Returns the SHA-1, serial, OU, CN team suffix and CN kind of a DER certificate."""
    result = subprocess.run(
        [
            "openssl",
            "x509",
            "-inform",
            "DER",
            "-noout",
            "-serial",
            "-subject",
            "-nameopt",
            "RFC2253",
        ],
        input=der,
        capture_output=True,
        check=True,
    )
    lines = result.stdout.decode("utf-8", "replace").splitlines()
    serial = next(line for line in lines if line.startswith("serial=")).split("=", 1)[1]
    subject = next((line for line in lines if line.startswith("subject=")), "")

    def field(name: str) -> str:
        match = re.search(rf"(?:^subject=|,){name}=([^,]*)", subject)
        return match.group(1) if match else ""

    common_name = field("CN")
    suffix = "NONE"
    if common_name.endswith(")") and "(" in common_name:
        suffix = common_name.rsplit("(", 1)[1].rstrip(")")
    return {
        "sha1": hashlib.sha1(der, usedforsecurity=False).hexdigest(),
        "serial": serial,
        "ou": field("OU"),
        "cn_suffix": suffix,
        "kind": common_name.split(":", 1)[0] if common_name else "UNKNOWN",
    }


def shortened(value: str, full: bool) -> str:
    if full or len(value) <= 12:
        return value
    return f"{value[:8]}...{value[-4:]}  (use --full for full)"


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


AUDIT_DIRECTORIES = (
    Path.home() / "Documents/profiles",
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
)


def audit(paths: list[str]) -> int:
    if not paths:
        present = [directory for directory in AUDIT_DIRECTORIES if directory.is_dir()]
        if not present:
            print("No profile directories found under:", file=sys.stderr)
            for directory in AUDIT_DIRECTORIES:
                print(f"  - {directory}", file=sys.stderr)
        paths = [
            str(path)
            for directory in present
            for path in sorted(directory.iterdir())
            if path.is_file()
            and path.suffix in {".provisionprofile", ".mobileprovision"}
        ]
    for path in paths:
        if not os.path.isfile(path):
            continue
        print(f"==> {os.path.basename(path)}")
        profile = decoded_profile(path)
        if profile is None:
            print("  decode_ok: false")
            continue
        entitlements = profile.get("Entitlements") or {}
        app_id = entitlements.get(
            "com.apple.application-identifier"
        ) or entitlements.get("application-identifier")
        suffix = (
            app_id.split(".", 1)[1]
            if isinstance(app_id, str) and "." in app_id
            else "UNKNOWN"
        )
        kinds = [
            certificate_facts(der)["kind"] for der in embedded_certificates(profile)
        ]
        print("  decode_ok: true")
        print(f"  bundle_id_suffix: {suffix}")
        print(f"  developer_certificate_kind: {','.join(kinds) or 'UNKNOWN'}")
        print(
            "  has_entitlement_hid_virtual_device: "
            f"{'com.apple.developer.hid.virtual.device' in entitlements}"
        )
    return 0


def cert_info(path: str, full: bool) -> int:
    if not os.path.isfile(path):
        print(f"ERROR: Missing file: {path}", file=sys.stderr)
        return 2
    facts = certificate_facts(Path(path).read_bytes())
    print(f"path: {path}")
    print(f"sha1: {shortened(facts['sha1'], full)}")
    print(f"serial: {shortened(facts['serial'], full)}")
    print(f"ou: {facts['ou']}")
    print(f"cn_suffix: {facts['cn_suffix']}")
    return 0


def profile_info(paths: list[str], full: bool) -> int:
    for path in map(os.path.expanduser, paths):
        print(f"==> {os.path.basename(path)}")
        if not os.path.isfile(path):
            print("  error: missing file")
            continue
        profile = decoded_profile(path)
        if profile is None:
            print("  error: could not decode profile")
            continue
        name = profile.get("Name")
        teams = profile.get("TeamIdentifier") or []
        team = (
            teams[0]
            if isinstance(teams, list) and teams and isinstance(teams[0], str)
            else None
        )
        print(f"  name: {name if isinstance(name, str) else 'UNKNOWN'}")
        print(f"  team_identifier: {team or 'UNKNOWN'}")
        certificates = embedded_certificates(profile)
        if not certificates:
            print("  embedded_cert: missing")
            continue
        print(f"  embedded_cert_count: {len(certificates)}")
        for index, der in enumerate(certificates):
            facts = certificate_facts(der)
            print(f"  embedded_cert[{index}]_sha1: {shortened(facts['sha1'], full)}")
            print(
                f"  embedded_cert[{index}]_serial: {shortened(facts['serial'], full)}"
            )
            print(f"  embedded_cert[{index}]_ou: {facts['ou']}")
            print(f"  embedded_cert[{index}]_cn_suffix: {facts['cn_suffix']}")
    return 0


def extract_certs(path: str, out_dir: str) -> int:
    profile = decoded_profile(os.path.expanduser(path))
    if profile is None:
        print("ERROR: could not decode provisioning profile", file=sys.stderr)
        return 2
    certificates = embedded_certificates(profile)
    if not certificates:
        print("ERROR: profile has no DeveloperCertificates", file=sys.stderr)
        return 2
    for index, der in enumerate(certificates):
        Path(out_dir, f"cert-{index}.der").write_bytes(der)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="profile_certs.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("audit").add_argument("paths", nargs="*")
    for name, nargs in (("cert-info", None), ("profile-info", "+")):
        command = commands.add_parser(name)
        command.add_argument("--full", action="store_true")
        command.add_argument("paths", nargs=nargs)
    extract = commands.add_parser("extract-certs")
    extract.add_argument("profile")
    extract.add_argument("out_dir")
    args = parser.parse_args(argv)
    if args.command == "audit":
        return audit(args.paths)
    if args.command == "cert-info":
        return cert_info(args.paths, args.full)
    if args.command == "profile-info":
        return profile_info(args.paths, args.full)
    return extract_certs(args.profile, args.out_dir)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
