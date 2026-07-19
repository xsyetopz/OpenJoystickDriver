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
DRIVER_DEVELOPMENT = PROFILES / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"
HOST_RELEASE = PROFILES / "OpenJoystickDriver_DevID.provisionprofile"
RELAY_BUNDLE_ID = "com.openjoystickdriver.VirtualHIDDevice"
LEGACY_USERCLIENT_VALUE = f"{RELAY_BUNDLE_ID}\ncom.openjoystickdriver.daemon"
PROJECT_ENV = pathlib.Path(__file__).resolve().parents[2] / ".env.dev"


def legacy_profile_mode() -> tuple[bool, str | None]:
    raw = os.environ.get("OJD_USE_LEGACY_DRIVERKIT_PROFILE")
    if raw is None and PROJECT_ENV.is_file():
        match = re.search(
            r"^\s*(?:export\s+)?OJD_USE_LEGACY_DRIVERKIT_PROFILE=[\"']?([^\"'\s#]+)",
            PROJECT_ENV.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        raw = match.group(1) if match else "0"
    raw = raw or "0"
    if raw not in {"0", "1"}:
        return False, "OJD_USE_LEGACY_DRIVERKIT_PROFILE must be 0 or 1"
    if raw == "0":
        return False, None
    if os.environ.get("OJD_ENV", "dev") != "dev":
        return False, "legacy DriverKit profile mode is forbidden for release signing"
    if os.environ.get("CI", "false") in {"true", "1"}:
        return False, "legacy DriverKit profile mode is forbidden in CI"
    return True, None


def decode_profile(path: pathlib.Path) -> dict:
    for command in (
        ["security", "cms", "-D", "-i", str(path)],
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", str(path)],
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
    pattern = re.compile(
        rf'^\s*\d+\)\s+([0-9A-Fa-f]{{40}})\s+"{re.escape(prefix)}:'
    )
    for line in result.stdout.splitlines():
        if match := pattern.search(line):
            found.add(match.group(1).lower())
    return found


def entitlement_errors(
    label: str, profile: dict, expected: dict[str, object]
) -> list[str]:
    entitlements = profile.get("Entitlements", {})
    errors = []
    for key, value in expected.items():
        actual = entitlements.get(key)
        if actual != value:
            errors.append(
                f"{label}: {key} is {actual!r}; expected {value!r}"
            )
    if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
        errors.append(f"{label}: remove DriverKit allow-any user-client access")
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

    legacy_mode, mode_error = legacy_profile_mode()
    errors = [mode_error] if mode_error else []
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
                    "com.apple.developer.driverkit.userclient-access": [
                        LEGACY_USERCLIENT_VALUE if legacy_mode else RELAY_BUNDLE_ID
                    ],
                },
            )
        )
    if driver is not None:
        errors.extend(
            entitlement_errors(
                "DriverKit development profile",
                driver,
                {
                    "com.apple.developer.driverkit": True,
                    "com.apple.developer.driverkit.family.hid.device": True,
                    "com.apple.developer.driverkit.transport.hid": True,
                    "com.apple.developer.driverkit.family.hid.eventservice": True,
                },
            )
        )

    if host is not None and driver is not None:
        common = (
            certificate_sha1s(host)
            & certificate_sha1s(driver)
            & apple_development
        )
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

    if legacy_mode:
        print("Development signing: READY (COMPATIBILITY OUTPUT ONLY)")
        print(
            "  [WARN] the selected host profile contains Apple's approved legacy "
            "DriverKit user-client value"
        )
        print(
            "  [OK] generated host signing omits DriverKit user-client access so "
            "the app can launch"
        )
        print("  [OK] Compatibility IOHIDUserDevice output remains available")
        print(
            "  [UNAVAILABLE] DriverKit relay diagnostics require the corrected "
            "host grant"
        )
        print(
            "  [ACTION] replace the host profile after Apple approves the corrected "
            "grant"
        )
    else:
        print("Development signing: READY")
    print("  [OK] host and DriverKit profiles share an installed Apple Development identity")
    print("  [OK] host Compatibility and system-extension entitlements are present")
    print("  [OK] required DriverKit profile entitlements are present")
    print()

    if not HOST_RELEASE.is_file():
        print("Publisher release signing: NOT CONFIGURED (optional for development)")
        print(f"  [SKIP] {HOST_RELEASE} is absent")
    else:
        release, release_errors = load("host Developer ID profile", HOST_RELEASE)
        if release is not None:
            release_errors.extend(
                entitlement_errors(
                    "host Developer ID profile",
                    release,
                    {
                        "com.apple.developer.system-extension.install": True,
                        "com.apple.developer.hid.virtual.device": True,
                        "com.apple.developer.driverkit.userclient-access": [RELAY_BUNDLE_ID],
                    },
                )
            )
            if not certificate_sha1s(release) & developer_id:
                release_errors.append(
                    "Developer ID profile does not match an installed Developer ID "
                    "Application identity/private key"
                )
        if release_errors:
            print("Publisher release signing: BLOCKED (development remains ready)")
            for error in release_errors:
                print(f"  [FAIL] {error}")
        else:
            print("Publisher host signing: READY")
            print("  [OK] Developer ID profile matches an installed signing identity")
            print("  DriverKit distribution signing/notarization still requires its release gate")

    print()
    print("Next development command:")
    print("  ./scripts/ojd rebuild dev")
    return 0


if __name__ == "__main__":
    sys.exit(main())
