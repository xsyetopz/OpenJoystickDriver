# Build options and limits

This article lists what works with each kind of OpenJoystickDriver (OJD) build.

## Build conditions

| Condition | Result |
| --- | --- |
| Development signing with the correct profile | `build install dev` needs the app profile and the `OpenJoystickDriver_XboxUSBDevice.provisionprofile` profile. It always builds the system extension. Only Macs in the profiles can run it. |
| Profile without the virtual device entitlement | The build scripts stop. |
| Ad-hoc signing for the app | No scripted build exists. |
| Ad-hoc signing for the system extension | `build dext` stops with "DriverKit extensions cannot use ad-hoc signing". |
| Plain `swift build` binary | It has no entitlements. Expected: OJD reads controllers and cannot publish the virtual controller. Not verified. |
| Build without the system extension | Everything works except Xbox One and Xbox Series controllers on USB. |
| Only the Command Line Tools, no Xcode | Not verified for `swift build` and `swift test`. |
| Tester DMG | Signed and notarized by the maintainer. It runs on macOS 12 or later and needs no Apple developer account. |

## Which controllers need the extension

Only these Xbox USB product IDs need the system extension: `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, and `0B12`. OJD talks to the extension only for these controllers.

## Security settings

SIP and AMFI stay on for every build type. Never disable them.

## Further reading

- [Building OpenJoystickDriver](building-openjoystickdriver.md)
- [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md)
- [Security model](../permissions-and-security/security-model.md)
