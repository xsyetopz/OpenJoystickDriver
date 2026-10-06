# Building From Source

Build OpenJoystickDriver yourself when you need a fix before the next tester build, and see what each kind of build can do.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Build OpenJoystickDriver

This section explains when to build OpenJoystickDriver (OJD) from source and how to run a signed build.

Most users do not need to build. Build only to get a fix before the next tester build. `CHANGELOG.md` lists what each build contains.

### Before You Begin

You need the following items:

- A Mac with the Xcode command-line tools. A few build steps need full Xcode.
- An Apple Developer team.
- Two development provisioning profiles, one for the app and one for the driver extension `com.openjoystickdriver.XboxUSBDevice`. The files must be named `OpenJoystickDriver.provisionprofile` and `OpenJoystickDriver_XboxUSBDevice.provisionprofile`. The app profile must include the `com.apple.developer.hid.virtual.device` entitlement, and its `com.apple.developer.driverkit.userclient-access` entitlement must name `com.openjoystickdriver.XboxUSBDevice`. The extension profile must include `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` with Apple's exact seven VID:PID pairs, and no HID entitlement. The default profile name is `OpenJoystickDriver (XboxUSBDevice)`. To use other profiles, set `DEXT_PROVISIONING_PROFILE` and `DEXT_BUILD_PROFILE`.
- The publisher team already has the `transport.usb` capability from Apple. Enable it on the `com.openjoystickdriver.XboxUSBDevice` App ID, then download the extension profile again.
- Your Mac in the list of devices in each profile.

An editor such as Visual Studio Code is enough to edit code. You do not need the Xcode IDE for daily work.

> [!WARNING]
> Keep SIP and AMFI on. Never disable them for any build.

There is no scripted unsigned or ad-hoc app build. The build scripts stop if the profile lacks the virtual device entitlement.

### Build and Install

1. Clone the repository and open the folder.

   ```shell
   git clone https://github.com/xsyetopz/OpenJoystickDriver.git
   cd OpenJoystickDriver
   ```

1. Install the helper tools.

   ```shell
   ./Scripts/ojd setup
   ```

1. Put both downloaded profile files in `~/Documents/Profiles` or in `~/Downloads`. Then set up signing.

   ```shell
   ./Scripts/ojd signing install-profiles
   ./Scripts/ojd signing configure
   ./Scripts/ojd signing doctor
   ```

   `signing install-profiles` copies the profiles to `~/Library/MobileDevice/Provisioning Profiles`. `signing configure` reads them from there.

1. Build and install the app.

   ```shell
   ./Scripts/ojd build install dev
   ```

   This command builds the system extension too. When the app profile has no `userclient-access` grant for `com.openjoystickdriver.XboxUSBDevice`, the build skips the extension and the app has no driver extension.

1. Open OJD from **Applications**.

The `signing doctor` command checks your signing setup. Fix each problem it reports before you build.

## Build Options and Limits

This section lists what works with each kind of OpenJoystickDriver (OJD) build.

### Build Conditions

| Condition | Result |
| --- | --- |
| Development signing with the correct profile | `build install dev` needs the app profile and the `OpenJoystickDriver_XboxUSBDevice.provisionprofile` profile. It builds the system extension. Only Macs in the profiles can run it. |
| Profile without the virtual device entitlement | The build scripts stop. |
| Ad-hoc signing for the app | No scripted build exists. |
| Ad-hoc signing for the system extension | `build dext` stops with "DriverKit extensions cannot use ad-hoc signing". |
| Plain `swift build` binary | It has no entitlements. Expected: OJD reads controllers and cannot publish the virtual controller. Not verified. |
| Extension profile without the exact `com.apple.developer.driverkit.transport.usb` entitlement | The build stops. |
| Only the Command Line Tools, no Xcode | Not verified for `swift build` and `swift test`. |
| Tester DMG | Signed and notarized by the maintainer. It runs on macOS 12 or later and needs no Apple developer account. |

### Which Controllers Need the Xbox USB Part

Only these Xbox USB product IDs need the driver extension: `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, and `0B12`. OJD talks to the extension only for these controllers.

### Security Settings

SIP and AMFI stay on for every build type. Never disable them.

## Further Reading

- [Xbox USB driver extension](Connecting-Controllers.md)
- [Security model](Permissions-and-Security.md)
- [Building from source (developer guide)](../docs/development/building-from-source.md)
- [Signing (developer guide)](../docs/development/signing.md)
