# Signing

## Contents

- [Signing diagnosis](#signing-diagnosis)
- [Entitlement shape](#entitlement-shape)

## Signing Diagnosis

**Definition.** The diagnosis runs in this order, and stops at the first failing step:

1. Rerun the signed operation (`./Scripts/ojd build install dev`), and follow its prompts. It installs discovered profiles and configures identities.
1. `./Scripts/ojd signing audit` compares the local assets with the expected ones.
1. `./Scripts/ojd signing configure` rewrites `.env.dev` or `.env.release` from the installed assets.
1. `./Scripts/ojd signing doctor` fails closed on any of these:
   - the DEXT profile (`OpenJoystickDriver_XboxUSBDevice.provisionprofile`, or `OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile` for release) is missing;
   - the host allowlist is not exactly `com.openjoystickdriver.XboxUSBDevice`;
   - the USB entitlement has the wrong shape;
   - a forbidden entitlement is present.
1. Inspect the artifacts directly:

   ```bash
   codesign -d --entitlements - --xml /Applications/OpenJoystickDriver.app
   security cms -D -i \
     ~/Library/MobileDevice/Provisioning\ Profiles/OpenJoystickDriver.provisionprofile
   ```

**Use when.** Any entitlement, profile, identity, or AMFI failure.

**Do not use when.** The failure is a compile error. That is not signing.

**Example.** The dev build installs, but creating a virtual `IOHIDUserDevice` fails. The cause is that the host development profile's device list does not include this Mac, so AMFI ignores `com.apple.developer.hid.virtual.device`. Add the Mac and regenerate the profile, then run `./Scripts/ojd signing install-profiles`.

**Verify.** `./Scripts/ojd signing doctor` passes, and `./Scripts/ojd check driverkit` passes.

## Entitlement Shape

**Definition.** The canonical shape is in `docs/development/signing.md`, under "Entitlement Ownership":

- The host app has `system-extension.install`, `driverkit.userclient-access` containing exactly `com.openjoystickdriver.XboxUSBDevice`, and `hid.virtual.device`. It never has `allow-any-userclient-access`. `hid.virtual.device` belongs to the app (`com.openjoystickdriver`) profile only, because it creates the virtual gamepads through `IOHIDUserDevice`.
- The single DEXT, `com.openjoystickdriver.XboxUSBDevice`, has only `driverkit` and `driverkit.transport.usb`. It has no `hid.virtual.device` entitlement, and Apple says that entitlement must not be in a DEXT.
- `driverkit.transport.usb` has exactly the seven approved Microsoft VID/PID pairs and no wildcard. The host profiles grant `driverkit.userclient-access` only for `com.openjoystickdriver.XboxUSBDevice`, so a DEXT with another bundle ID is not embedded. Enable `transport.usb` on the `com.openjoystickdriver.XboxUSBDevice` App ID and regenerate the DriverKit profile instead of requesting it again.

**Use when.** Reviewing a signing change, or a profile regenerated after a capability change.

**Do not use when.** A controller outside those seven pairs needs support. Such a controller uses the app's direct IOUSBHost route (`ojd-controller-catalog`), not a DriverKit grant.

**Verify.** `codesign -d --entitlements - --xml` on the embedded `.dext` lists `driverkit` and `driverkit.transport.usb`, with the seven pairs and nothing more when the USB grant exists.
