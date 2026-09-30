# Building OpenJoystickDriver

This article explains when to build OpenJoystickDriver (OJD) from source and how to run a signed build.

Most users do not need to build. Build only to get a fix before the next tester build. `CHANGELOG.md` lists what each build contains.

## Before you begin

You need the following items:

- A Mac with the Xcode command-line tools. A few build steps need full Xcode.
- An Apple Developer team.
- Two development provisioning profiles, one for the app and one for the system extension. The files must be named `OpenJoystickDriver.provisionprofile` and `OpenJoystickDriver_XboxUSBDevice.provisionprofile`. The app profile must include the `com.apple.developer.hid.virtual.device` entitlement. The extension profile must include the system extension install entitlement.
- Your Mac in the list of devices in each profile.

An editor such as Visual Studio Code is enough to edit code. You do not need the Xcode IDE for daily work.

> [!WARNING]
> Keep SIP and AMFI on. Never disable them for any build.

There is no scripted unsigned or ad-hoc app build. The build scripts stop if the profile lacks the virtual device entitlement.

## Build and install

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

   This command always builds the system extension too.

1. Open OJD from **Applications**.

The `signing doctor` command checks your signing setup. Fix each problem it reports before you build.

## Further reading

- [Build options and limits](build-options-and-limits.md)
- [Building from source (developer guide)](../../contributing/development/building-from-source.md)
- [Signing (developer guide)](../../contributing/development/signing.md)
