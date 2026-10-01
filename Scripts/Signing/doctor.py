"""Diagnose development and optional publisher signing without exposing secrets."""

from __future__ import annotations

import hashlib
import json
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
DRIVER_RELEASE = PROFILES / "OpenJoystickDriver_VirtualHIDDevice_DevID.provisionprofile"
DEXT_BUNDLE_ID = "com.openjoystickdriver.VirtualHIDDevice"
HID_FACTORY_KEYS = (
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
)
USERCLIENT_ACCESS = "com.apple.developer.driverkit.userclient-access"
USB_TRANSPORT = "com.apple.developer.driverkit.transport.usb"
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


def host_platform_uuid() -> str | None:
    result = subprocess.run(
        ["ioreg", "-d2", "-c", "IOPlatformExpertDevice"],
        capture_output=True,
        check=False,
        text=True,
    )
    for line in result.stdout.splitlines():
        if "IOPlatformUUID" not in line:
            continue
        _, _, value = line.partition("=")
        uuid = value.strip().strip('"')
        return uuid or None
    return None


def _device_id_key(value: str) -> str:
    return value.replace("-", "").casefold()


def _hardware_data_type() -> dict:
    result = subprocess.run(
        ["system_profiler", "SPHardwareDataType", "-json"],
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0 or not result.stdout:
        return {}
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    items = payload.get("SPHardwareDataType")
    if not isinstance(items, list) or not items:
        return {}
    first = items[0]
    return first if isinstance(first, dict) else {}


def host_development_ids() -> list[str]:
    ids: list[str] = []
    seen: set[str] = set()

    def add(value: object) -> None:
        if not isinstance(value, str) or not value:
            return
        key = _device_id_key(value)
        if key in seen:
            return
        seen.add(key)
        ids.append(value)

    hardware = _hardware_data_type()
    add(hardware.get("provisioning_UDID"))
    add(hardware.get("platform_UUID"))
    add(host_platform_uuid())
    return ids


def development_profile_covers_host(profile: dict) -> bool | None:
    if profile.get("ProvisionsAllDevices") is True:
        return True
    devices = profile.get("ProvisionedDevices")
    if not devices:
        return True
    if isinstance(devices, str):
        entries = [devices]
    elif isinstance(devices, list):
        entries = [item for item in devices if isinstance(item, str)]
    else:
        return True
    if not entries:
        return True
    host_ids = host_development_ids()
    if not host_ids:
        return None
    host_keys = {_device_id_key(item) for item in host_ids}
    return any(_device_id_key(entry) in host_keys for entry in entries)


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


def userclient_ungranted(value: object) -> bool:
    """True when the profile has no user-client grant for this DEXT, such as a grant that
    names only another bundle ID. A development build then omits the DEXT."""
    if value is None:
        return True
    return (
        isinstance(value, list)
        and all(isinstance(item, str) for item in value)
        and DEXT_BUNDLE_ID not in value
    )


def userclient_access_errors(
    label: str, profile: dict, *, allow_ungranted: bool = False
) -> list[str]:
    value = profile.get("Entitlements", {}).get(USERCLIENT_ACCESS)
    if allow_ungranted and userclient_ungranted(value):
        return []
    if value != [DEXT_BUNDLE_ID]:
        expected = [DEXT_BUNDLE_ID]
        return [f"{label}: {USERCLIENT_ACCESS} is {value!r}; expected {expected!r}"]
    return []


def dext_profile_errors(label: str, profile: dict) -> tuple[bool, list[str]]:
    """Returns whether the profile grants the USB transport, and its errors.

    Without Apple's transport.usb grant the build signs the HID factory personality only.
    """
    expected: dict[str, object] = {"com.apple.developer.driverkit": True}
    expected.update(dict.fromkeys(HID_FACTORY_KEYS, True))
    errors = entitlement_errors(
        label,
        profile,
        expected,
        forbidden=("com.apple.developer.hid.virtual.device",),
    )
    usb = profile.get("Entitlements", {}).get(USB_TRANSPORT)
    if usb is not None and usb != PRODUCTION_USB:
        errors.append(
            f"{label}: {USB_TRANSPORT} differs from Apple's exact seven-device grant"
        )
    return usb == PRODUCTION_USB, errors


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
    usb_granted = False
    userclient_granted = False
    userclient_value = None

    if host is not None:
        errors.extend(
            entitlement_errors(
                "host development profile",
                host,
                {
                    "com.apple.developer.system-extension.install": True,
                    "com.apple.developer.hid.virtual.device": True,
                },
            )
        )
        errors.extend(
            userclient_access_errors(
                "host development profile", host, allow_ungranted=True
            )
        )
        userclient_value = host.get("Entitlements", {}).get(USERCLIENT_ACCESS)
        userclient_granted = not userclient_ungranted(userclient_value)
        if development_profile_covers_host(host) is False:
            errors.append(
                "host development profile does not include this Mac; "
                "IOHIDUserDevice virtual device creation will fail"
            )
    # Without the user-client grant the build omits the DEXT and never reads its profile.
    driver_needed = (
        host is None
        or userclient_granted
        or driver_errors
        != [f"DriverKit development profile is missing: {DRIVER_DEVELOPMENT}"]
    )
    if driver_needed:
        errors.extend(driver_errors)
    if driver is not None:
        usb_granted, driver_entitlement_errors = dext_profile_errors(
            "DriverKit development profile", driver
        )
        errors.extend(driver_entitlement_errors)

    if host is not None and driver is not None:
        common = certificate_sha1s(host) & certificate_sha1s(driver) & apple_development
        if not common:
            errors.append(
                "host and DriverKit development profiles do not share an installed "
                "Apple Development signing identity/private key"
            )
    elif host is not None and not certificate_sha1s(host) & apple_development:
        errors.append(
            "host development profile does not match an installed Apple Development "
            "signing identity/private key"
        )

    development_blocked = bool(errors)
    if development_blocked:
        print("Development signing: BLOCKED")
        for error in errors:
            print(f"  [FAIL] {error}")
        print()
    else:
        print("Development signing: READY")
        if driver is None:
            print("  [OK] host profile matches an installed Apple Development identity")
        else:
            print(
                "  [OK] host and DriverKit profiles share an installed Apple Development "
                "identity"
            )
        print("  [OK] host virtual HID and system-extension entitlements are present")
        if driver is None:
            print(f"  [SKIP] {driver_errors[0]}; not needed while the DEXT is omitted")
        else:
            print("  [OK] required DriverKit profile entitlements are present")
        if userclient_granted:
            print(f"  [OK] host profile grants user-client access to {DEXT_BUNDLE_ID}")
        else:
            print(
                f"  [SKIP] host profile {USERCLIENT_ACCESS} is {userclient_value!r}; "
                "development builds omit the DEXT and use IOHIDUserDevice until Apple "
                f"grants it for {DEXT_BUNDLE_ID}"
            )
        if driver is not None:
            report_usb_grant(usb_granted)
        print()

    release_ready = report_release_signing(developer_id)

    if development_blocked:
        print(
            "Obtain the assets described in contributing/development/signing.md, then run:"
        )
        print("  ./Scripts/ojd signing install-profiles")
        print("  ./Scripts/ojd signing configure")
        if release_ready:
            print()
            print(
                "Virtual HID on this Mac: Apple Development device list excludes the host."
            )
            print("Developer ID profiles provision all Macs; use:")
            print("  OJD_ENV=release ./Scripts/ojd build release")
        return 1

    print()
    print("Next development command:")
    print("  ./Scripts/ojd build install dev")
    return 0


def report_usb_grant(usb_granted: bool) -> None:
    if usb_granted:
        print("  [OK] DriverKit profile contains Apple's exact seven-device USB grant")
    else:
        print(
            "  [SKIP] DriverKit profile has no USB transport grant; builds are "
            "factory-only (no Xbox USB ownership) until the profile includes it for "
            f"{DEXT_BUNDLE_ID}"
        )


def report_release_signing(developer_id: set[str]) -> bool:
    if not HOST_RELEASE.is_file() and not DRIVER_RELEASE.is_file():
        print("Publisher release signing: NOT CONFIGURED (optional for development)")
        print("  [SKIP] both Developer ID profiles are absent")
        print()
        return False

    release, release_errors = load("host Developer ID profile", HOST_RELEASE)
    driver_release, driver_release_errors = load(
        "DriverKit Developer ID profile", DRIVER_RELEASE
    )
    release_errors.extend(driver_release_errors)
    usb_granted = False
    if release is not None:
        release_errors.extend(
            entitlement_errors(
                "host Developer ID profile",
                release,
                {
                    "com.apple.developer.system-extension.install": True,
                    "com.apple.developer.hid.virtual.device": True,
                },
            )
        )
        release_errors.extend(
            userclient_access_errors("host Developer ID profile", release)
        )
        if not certificate_sha1s(release) & developer_id:
            release_errors.append(
                "Developer ID profile does not match an installed Developer ID "
                "Application identity/private key"
            )
    if driver_release is not None:
        usb_granted, driver_entitlement_errors = dext_profile_errors(
            "DriverKit Developer ID profile", driver_release
        )
        release_errors.extend(driver_entitlement_errors)
        if not certificate_sha1s(driver_release) & developer_id:
            release_errors.append(
                "DriverKit Developer ID profile does not match an installed "
                "Developer ID Application identity/private key"
            )
    if release_errors:
        print("Publisher release signing: BLOCKED")
        for error in release_errors:
            print(f"  [FAIL] {error}")
        print()
        return False

    print("Publisher release signing: READY")
    print("  [OK] each profile matches an installed Developer ID identity")
    report_usb_grant(usb_granted)
    print()
    return True


if __name__ == "__main__":
    sys.exit(main())
