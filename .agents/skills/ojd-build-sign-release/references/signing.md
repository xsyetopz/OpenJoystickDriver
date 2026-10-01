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
   - the host allowlist is not exactly `com.openjoystickdriver.VirtualHIDDevice`;
   - the USB entitlement, when present, has the wrong shape;
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

- The host app has `system-extension.install`, `driverkit.userclient-access` containing exactly `com.openjoystickdriver.VirtualHIDDevice`, and `hid.virtual.device`. It never has `allow-any-userclient-access`. A development host profile without a grant for that bundle ID builds the app without `userclient-access` and without the DEXT (`IOHIDUserDevice` fallback). Release still requires the exact grant.
- The single DEXT, `com.openjoystickdriver.VirtualHIDDevice`, has `driverkit`, `driverkit.family.hid.device`, `driverkit.transport.hid`, and `driverkit.family.hid.eventservice`. It has no virtual-HID (`hid.virtual.device`) entitlement.
- `driverkit.transport.usb` is optional. When present it has exactly the seven approved Microsoft VID/PID pairs and no wildcard. Without it the build signs factory-only (the `HIDFactory` personality, no Xbox USB ownership via the `XboxUSB` personality). The team's `transport.usb` capability is already assigned; enable it on the `com.openjoystickdriver.VirtualHIDDevice` App ID and regenerate the DriverKit profile instead of requesting it again.

**Use when.** Reviewing a signing change, or a profile regenerated after a capability change.

**Do not use when.** A controller outside those seven pairs needs support. Such a controller uses the app's direct IOUSBHost route (`ojd-controller-catalog`), not a DriverKit grant.

**Verify.** `codesign -d --entitlements - --xml` on the embedded `.dext` lists the four HID/DriverKit entitlements, and the seven pairs and nothing more when the USB grant exists.
