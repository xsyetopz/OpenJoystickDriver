# Building From Source

Build OpenJoystickDriver yourself to get a fix before the next tester build.

## Build OpenJoystickDriver

Most users don't need to build. `CHANGELOG.md` lists what each build contains. OpenJoystickDriver (OJD) runs only as a signed build.

### Before You Begin

You need these items:

- A Mac with the Xcode command-line tools. The [Xbox USB driver](Glossary.md#terms) and Shortcuts actions need full Xcode.
- An Apple Developer team.
- Two development provisioning profiles, one for the app and one for the Xbox USB driver (`com.openjoystickdriver.XboxUSBDevice`). Name the files `OpenJoystickDriver.provisionprofile` and `OpenJoystickDriver_XboxUSBDevice.provisionprofile`.
  - The app profile needs the `com.apple.developer.hid.virtual.device` entitlement. Its `com.apple.developer.driverkit.userclient-access` entitlement must name `com.openjoystickdriver.XboxUSBDevice`.
  - The Xbox USB driver profile needs `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` with Apple's exact seven VID:PID pairs, and no HID entitlement.
  - `just signing-install-profiles` copies the files under those names. `just signing-configure` writes their paths to `.env.dev`.
- The `transport.usb` capability from Apple. Enable it on the `com.openjoystickdriver.XboxUSBDevice` App ID, then download the Xbox USB driver profile again. The publisher team already has it.
- Your Mac in the list of devices in each provisioning profile.

### Build and Install

1. Clone the repository and open the folder.

   ```shell
   git clone https://github.com/xsyetopz/OpenJoystickDriver.git
   cd OpenJoystickDriver
   ```

2. Install the helper tools.

   ```shell
   just setup
   ```

3. Put both downloaded profile files in `~/Documents/Profiles` or in `~/Downloads`. Then set up signing.

   ```shell
   just signing-install-profiles
   just signing-configure
   ```

   `signing install-profiles` copies the profiles to `~/Library/MobileDevice/Provisioning Profiles`. `signing configure` reads them from there.

4. Build and install the app.

   ```shell
   just install-dev
   ```

   This also builds the Xbox USB driver. Without the `userclient-access` grant, the build skips the driver.

5. Open OJD from **Applications**.

## Build Options and Limits

### Build Conditions

| Condition | Result |
| --- | --- |
| Development signing with the correct profiles | `just install-dev` builds the app and the Xbox USB driver. Only Macs in the profiles can run it. |
| App profile without the `com.apple.developer.hid.virtual.device` entitlement | The build stops. |
| Ad-hoc signing for the app | No script builds it. |
| Ad-hoc signing for the Xbox USB driver | `just build-dext` stops with `DriverKit extensions cannot use ad-hoc signing`. |
| Plain `swift build` binary | No entitlements. Not verified: OJD reads controllers but can't publish the [virtual gamepad](Glossary.md#terms). |
| Xbox USB driver profile without the exact `transport.usb` entitlement | The build stops. |
| Only the Command Line Tools, no Xcode | Install [swiftly](https://www.swift.org/install/macos/) before `just setup`. `just install-dev` builds the app without the Xbox USB driver, and Shortcuts lists none of its actions. |
| Tester DMG | Signed and notarized by the maintainer. Runs on macOS 12 or later. Needs no Apple developer account. |

### Which Controllers Need the Xbox USB Driver

Only these USB product IDs use the Xbox USB driver: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`.

### Security Settings

Keep SIP and AMFI on for every build. Never turn them off.

## Further Reading

- [Xbox USB driver](Connecting-Controllers.md#xbox-usb-driver)
- [Security model](Permissions-and-Security.md#security-model)
- [Building from source (developer guide)](../docs/development/building-from-source.md)
- [Signing (developer guide)](../docs/development/signing.md)
