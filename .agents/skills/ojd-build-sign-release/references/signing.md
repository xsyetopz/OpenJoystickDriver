# Signing

## Contents

- [Signing diagnosis](#signing-diagnosis)
- [Entitlement shape](#entitlement-shape)

## Signing diagnosis

**Definition.** The diagnosis runs in this order, and stops at the first failing step:

1. Rerun the signed operation (`./Scripts/ojd build install dev`), and follow its prompts. It installs discovered profiles and configures identities.
1. `./Scripts/ojd signing audit` compares the local assets with the expected ones.
1. `./Scripts/ojd signing configure` rewrites `.env.dev` or `.env.release` from the installed assets.
1. `./Scripts/ojd signing doctor` fails closed on any of these:
   - the DEXT profile is missing;
   - the host allowlist names the deleted `VirtualHIDDevice`;
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

## Entitlement shape

**Definition.** The canonical shape is in `contributing/development/signing.md`, under "Entitlement Ownership":

- The host app has `system-extension.install`, `driverkit.userclient-access` set to exactly `["com.openjoystickdriver.XboxUSBDevice"]`, and `hid.virtual.device`. It never has `allow-any-userclient-access`.
- The DEXT has `driverkit` and `driverkit.transport.usb`, with exactly the seven approved Microsoft VID/PID pairs. It has no wildcard, no virtual-HID entitlement, and no HIDDriverKit entitlement.

**Use when.** Reviewing a signing change, or a profile regenerated after a capability change.

**Do not use when.** A controller outside those seven pairs needs support. Such a controller uses the app's direct IOUSBHost route (`ojd-controller-catalog`), not a DriverKit grant.

**Verify.** `codesign -d --entitlements - --xml` on the embedded `.dext` lists the seven pairs and nothing more.
