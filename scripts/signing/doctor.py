#!/usr/bin/env python3
"""Diagnose development and optional publisher signing without exposing secrets."""

from __future__ import annotations

import hashlib
import os
import pathlib
import plistlib
import re
import subprocess
import sys

PROFILES = pathlib.Path(
    os.environ.get(
        "OJD_PROFILES_DIR",
        "~/Library/MobileDevice/Provisioning Profiles",
    )
).expanduser()
HOST_DEVELOPMENT = PROFILES / "OpenJoystickDriver.provisionprofile"
DRIVER_DEVELOPMENT = PROFILES / "OpenJoystickDriver_XboxUSBDevice.provisionprofile"
HOST_RELEASE = PROFILES / "OpenJoystickDriver_DevID.provisionprofile"
DRIVER_RELEASE = PROFILES / "OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile"
DEXT_BUNDLE_ID = "com.openjoystickdriver.XboxUSBDevice"
PRODUCTION_USB = [
    {"idVendor": 1118, "idProduct": 721},
    {"idVendor": 1118, "idProduct": 746},
    {"idVendor": 1118, "idProduct": 2834},
    {"idVendor": 1118, "idProduct": 2816},
    {"idVendor": 1118, "idProduct": 739},
    {"idVendor": 1118, "idProduct": 2826},
    {"idVendor": 1118, "idProduct": 733},
]


def decode_profile(path: pathlib.Path) -> dict:
    for command in (
        ["security", "cms", "-D", "-i", str(path)],
        [
            "openssl",
            "smime",
            "-inform",
            "der",
            "-verify",
            "-noverify",
            "-in",
            str(path),
        ],
    ):
        result = subprocess.run(command, capture_output=True, check=False)
        if result.returncode == 0 and result.stdout:
            raw = result.stdout
            if b"<?xml" in raw:
                raw = raw[raw.index(b"<?xml") :]
            return plistlib.loads(raw)
    raise ValueError("could not decode profile")


def certificate_sha1s(profile: dict) -> set[str]:
    return {
        hashlib.sha1(bytes(certificate), usedforsecurity=False).hexdigest()
        for certificate in profile.get("DeveloperCertificates", [])
        if isinstance(certificate, (bytes, bytearray))
    }


def identities(prefix: str) -> set[str]:
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        check=False,
        text=True,
    )
    found: set[str] = set()
    pattern = re.compile(rf'^\s*\d+\)\s+([0-9A-Fa-f]{{40}})\s+"{re.escape(prefix)}:')
    for line in result.stdout.splitlines():
        if match := pattern.search(line):
            found.add(match.group(1).lower())
    return found


def entitlement_errors(
    label: str,
    profile: dict,
    expected: dict[str, object],
    forbidden: tuple[str, ...] = (),
) -> list[str]:
    entitlements = profile.get("Entitlements", {})
    errors = []
    for key, value in expected.items():
        actual = entitlements.get(key)
        if actual != value:
            errors.append(f"{label}: {key} is {actual!r}; expected {value!r}")
    if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
        errors.append(f"{label}: remove DriverKit allow-any user-client access")
    for key in forbidden:
        if key in entitlements:
            errors.append(f"{label}: remove forbidden entitlement {key}")
    return errors


def load(label: str, path: pathlib.Path) -> tuple[dict | None, list[str]]:
    if not path.is_file():
        return None, [f"{label} is missing: {path}"]
    try:
        return decode_profile(path), []
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        return None, [f"{label} cannot be decoded: {path} ({error})"]


def main() -> int:
    print("OpenJoystickDriver signing doctor")
    print()

    apple_development = identities("Apple Development")
    developer_id = identities("Developer ID Application")
    print(f"Apple Development identities: {len(apple_development)}")
    print(f"Developer ID Application identities: {len(developer_id)}")
    print()

    errors = []
    host, host_errors = load("host development profile", HOST_DEVELOPMENT)
    errors.extend(host_errors)
    driver, driver_errors = load("DriverKit development profile", DRIVER_DEVELOPMENT)
    errors.extend(driver_errors)

    if host is not None:
        errors.extend(
            entitlement_errors(
                "host development profile",
                host,
                {
                    "com.apple.developer.system-extension.install": True,
                    "com.apple.developer.hid.virtual.device": True,
                    "com.apple.developer.driverkit.userclient-access": [DEXT_BUNDLE_ID],
                },
            )
        )
    if driver is not None:
        errors.extend(
            entitlement_errors(
                "DriverKit development profile",
                driver,
                {"com.apple.developer.driverkit": True},
                forbidden=(
                    "com.apple.developer.hid.virtual.device",
                    "com.apple.developer.driverkit.family.hid.device",
                    "com.apple.developer.driverkit.transport.hid",
                    "com.apple.developer.driverkit.family.hid.eventservice",
                ),
            )
        )
        errors.extend(
            entitlement_errors(
                "DriverKit development profile",
                driver,
                {"com.apple.developer.driverkit.transport.usb": PRODUCTION_USB},
            )
        )

    if host is not None and driver is not None:
        common = certificate_sha1s(host) & certificate_sha1s(driver) & apple_development
        if not common:
            errors.append(
                "host and DriverKit development profiles do not share an installed "
                "Apple Development signing identity/private key"
            )

    if errors:
        print("Development signing: BLOCKED")
        for error in errors:
            print(f"  [FAIL] {error}")
        print()
        print("Obtain the assets described in docs/development/signing.md, then run:")
        print("  ./scripts/ojd signing install-profiles")
        print("  ./scripts/ojd signing configure")
        return 1

    print("Development signing: READY")
    print(
        "  [OK] host and DriverKit profiles share an installed Apple Development identity"
    )
    print("  [OK] host Compatibility and system-extension entitlements are present")
    print("  [OK] required DriverKit profile entitlements are present")
    print()

    if not HOST_RELEASE.is_file() and not DRIVER_RELEASE.is_file():
        print("Publisher release signing: NOT CONFIGURED (optional for development)")
        print("  [SKIP] both Developer ID profiles are absent")
    else:
        release, release_errors = load("host Developer ID profile", HOST_RELEASE)
        driver_release, driver_release_errors = load(
            "DriverKit Developer ID profile", DRIVER_RELEASE
        )
        release_errors.extend(driver_release_errors)
        if release is not None:
            release_errors.extend(
                entitlement_errors(
                    "host Developer ID profile",
                    release,
                    {
                        "com.apple.developer.system-extension.install": True,
                        "com.apple.developer.hid.virtual.device": True,
                        "com.apple.developer.driverkit.userclient-access": [
                            DEXT_BUNDLE_ID
                        ],
                    },
                )
            )
            if not certificate_sha1s(release) & developer_id:
                release_errors.append(
                    "Developer ID profile does not match an installed Developer ID "
                    "Application identity/private key"
                )
        if driver_release is not None:
            release_errors.extend(
                entitlement_errors(
                    "DriverKit Developer ID profile",
                    driver_release,
                    {
                        "com.apple.developer.driverkit": True,
                        "com.apple.developer.driverkit.transport.usb": PRODUCTION_USB,
                    },
                    forbidden=(
                        "com.apple.developer.hid.virtual.device",
                        "com.apple.developer.driverkit.family.hid.device",
                        "com.apple.developer.driverkit.transport.hid",
                        "com.apple.developer.driverkit.family.hid.eventservice",
                    ),
                )
            )
            if not certificate_sha1s(driver_release) & developer_id:
                release_errors.append(
                    "DriverKit Developer ID profile does not match an installed "
                    "Developer ID Application identity/private key"
                )
        if release_errors:
            print("Publisher release signing: BLOCKED (development remains ready)")
            for error in release_errors:
                print(f"  [FAIL] {error}")
        else:
            print("Publisher release signing: READY")
            print("  [OK] each profile matches an installed Developer ID identity")
            print("  [OK] DriverKit profile contains Apple's exact seven-device grant")

    print()
    print("Next development command:")
    print("  ./scripts/ojd rebuild dev")
    return 0


if __name__ == "__main__":
    sys.exit(main())
