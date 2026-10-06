"""Behavior tests for the provisioning-profile checks in signing configure and doctor."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from Scripts.Signing import configure, doctor

DEXT = "com.openjoystickdriver.XboxUSBDevice"
USB = "com.apple.developer.driverkit.transport.usb"
FORBIDDEN_DEXT_KEYS = (
    "com.apple.developer.hid.virtual.device",
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
    "com.apple.developer.driverkit.allow-any-userclient-access",
)
USERCLIENT = "com.apple.developer.driverkit.userclient-access"
HOST = {
    "com.apple.developer.system-extension.install": True,
    "com.apple.developer.hid.virtual.device": True,
    USERCLIENT: [DEXT],
}
FULL_DEXT = {
    "com.apple.developer.driverkit": True,
    USB: doctor.PRODUCTION_USB,
}


def without(entitlements: dict, key: str) -> dict:
    return {name: value for name, value in entitlements.items() if name != key}


class ConfigureProfileTests(unittest.TestCase):
    def check(self, function, entitlements: dict, **kwargs) -> None:
        with patch.object(
            configure, "decode_profile", return_value={"Entitlements": entitlements}
        ):
            function("profile", "label", **kwargs)

    def test_dext_profile_accepts_exact_usb_grant(self) -> None:
        self.check(configure.require_dext_profile, FULL_DEXT)

    def test_dext_profile_rejects_missing_driverkit_or_usb_grant(self) -> None:
        for key in FULL_DEXT:
            with self.subTest(key=key), self.assertRaises(SystemExit):
                self.check(configure.require_dext_profile, without(FULL_DEXT, key))

    def test_dext_profile_rejects_wrong_usb_and_forbidden_keys(self) -> None:
        wrong_usb = (
            [],
            doctor.PRODUCTION_USB[:-1],
            [*doctor.PRODUCTION_USB, {"idVendor": 1118, "idProduct": 1}],
        )
        for entitlements in (
            *({**FULL_DEXT, USB: value} for value in wrong_usb),
            *({**FULL_DEXT, key: True} for key in FORBIDDEN_DEXT_KEYS),
        ):
            with self.subTest(entitlements=entitlements), self.assertRaises(SystemExit):
                self.check(configure.require_dext_profile, entitlements)

    def test_host_profile_userclient_states(self) -> None:
        self.check(configure.require_host_profile, HOST)
        self.check(
            configure.require_host_profile,
            without(HOST, USERCLIENT),
            allow_ungranted_userclient=True,
        )
        with self.assertRaises(SystemExit):
            self.check(configure.require_host_profile, without(HOST, USERCLIENT))
        self.check(
            configure.require_host_profile,
            {**HOST, USERCLIENT: ["com.example.OldDriver"]},
            allow_ungranted_userclient=True,
        )
        for value in ([DEXT, "other"], "*"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.check(
                    configure.require_host_profile,
                    {**HOST, USERCLIENT: value},
                    allow_ungranted_userclient=True,
                )


class DoctorProfileTests(unittest.TestCase):
    def test_userclient_access_states(self) -> None:
        granted = {"Entitlements": HOST}
        absent = {"Entitlements": without(HOST, USERCLIENT)}
        wrong = {"Entitlements": {**HOST, USERCLIENT: [DEXT, "other"]}}
        self.assertEqual(doctor.userclient_access_errors("host", granted), [])
        self.assertEqual(
            doctor.userclient_access_errors("host", absent, allow_ungranted=True), []
        )
        renamed = {"Entitlements": {**HOST, USERCLIENT: ["com.example.OldDriver"]}}
        self.assertEqual(
            doctor.userclient_access_errors("host", renamed, allow_ungranted=True), []
        )
        self.assertEqual(len(doctor.userclient_access_errors("host", absent)), 1)
        self.assertEqual(
            len(doctor.userclient_access_errors("host", wrong, allow_ungranted=True)), 1
        )

    def test_dext_profile_accepts_exact_usb_grant(self) -> None:
        self.assertEqual(
            doctor.dext_profile_errors("dext", {"Entitlements": FULL_DEXT}), []
        )

    def test_dext_profile_requires_driverkit_and_exact_usb_grant(self) -> None:
        for key in FULL_DEXT:
            with self.subTest(key=key):
                profile = {"Entitlements": without(FULL_DEXT, key)}
                self.assertEqual(len(doctor.dext_profile_errors("dext", profile)), 1)
        for value in ([], doctor.PRODUCTION_USB[:-1]):
            with self.subTest(usb=value):
                profile = {"Entitlements": {**FULL_DEXT, USB: value}}
                self.assertEqual(len(doctor.dext_profile_errors("dext", profile)), 1)

    def test_dext_profile_rejects_forbidden_entitlements(self) -> None:
        for key in FORBIDDEN_DEXT_KEYS:
            with self.subTest(key=key):
                profile = {"Entitlements": {**FULL_DEXT, key: True}}
                self.assertTrue(doctor.dext_profile_errors("dext", profile))


if __name__ == "__main__":
    unittest.main()
