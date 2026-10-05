# Signing the App and VirtualHIDDevice DEXT

OpenJoystickDriver has two independently provisioned code items:

- host app: `com.openjoystickdriver`
- DriverKit extension: `com.openjoystickdriver.VirtualHIDDevice`, with the `HIDFactory` and `XboxUSB` personalities

Follow [Kevin Elliott's DEXT signing guide](https://developer.apple.com/forums/thread/809202). DriverKit entitlement values are customized provisioning data; do not infer, broaden, or repair a profile in source.

## Entitlement Ownership

The host app requires:

- `com.apple.developer.system-extension.install = true`
- `com.apple.developer.driverkit.userclient-access` containing exactly `com.openjoystickdriver.VirtualHIDDevice`
- `com.apple.developer.hid.virtual.device = true`
- its profile's application and team identifiers

The host allowlist must never use `com.apple.developer.driverkit.allow-any-userclient-access`.

The DEXT profile requires `com.apple.developer.driverkit`, `com.apple.developer.driverkit.family.hid.device`, `com.apple.developer.driverkit.transport.hid`, and `com.apple.developer.driverkit.family.hid.eventservice`. `com.apple.developer.driverkit.transport.usb` is optional. When the profile has it, development and Developer ID signing use the same Apple-issued restricted USB value:

```xml
<key>com.apple.developer.driverkit.transport.usb</key>
<array>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>721</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>746</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>2834</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>2816</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>739</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>2826</integer></dict>
  <dict><key>idVendor</key><integer>1118</integer><key>idProduct</key><integer>733</integer></dict>
</array>
```

These are `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`. The DEXT must not contain the HID virtual-device entitlement (`com.apple.developer.hid.virtual.device`).

Without the `transport.usb` entitlement, the build signs factory-only: the `HIDFactory` personality (which matches `IOUserResources` and runs with no controller attached) works, and the `XboxUSB` personality does not own Microsoft GIP interfaces. The team's `transport.usb` capability (VendorID and ProductID) is already assigned, so no new Apple request is needed: enable it on the `com.openjoystickdriver.VirtualHIDDevice` App ID and regenerate the DriverKit profile. `OJD_DRIVERKIT_WITHOUT_USB=1` forces factory-only generation and validation, and `./Scripts/ojd driverkit generate --without-usb-personality` generates it.

Without a user-client grant for `com.openjoystickdriver.VirtualHIDDevice`, a development build omits the DEXT. This covers a host development profile that has no `userclient-access` key, or one whose list names only other bundle IDs (such as the pre-rename `com.openjoystickdriver.XboxUSBDevice`). The build signs the app without `userclient-access`, embeds no system extension, and skips activation. The app then publishes virtual gamepads through `IOHIDUserDevice`, and no DEXT routes are available, including Xbox USB ownership. The doctor reports this as skipped. In that case it also skips a missing DriverKit development profile. Release builds and Developer ID profiles still require the exact grant. Apple grants `userclient-access` per team and per DEXT bundle ID, so request it for `com.openjoystickdriver.VirtualHIDDevice` ([Requesting entitlements for DriverKit development](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development)), then regenerate the host profiles.

The canonical authored DEXT entitlement input is the union `Sources/DriverKitGenerator/Entitlements/VirtualHIDDevice.entitlements`.

## Development Profiles

Use Apple Development signing and separate profiles for the app and DEXT. Default local paths:

```text
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile
```

`DEXT_PROVISIONING_PROFILE` overrides the DEXT profile path, and `DEXT_BUILD_PROFILE` overrides the embedded profile name (default `OpenJoystickDriver (VirtualHIDDevice)`).

The host development profile's device list must include this Mac. Otherwise AMFI ignores `com.apple.developer.hid.virtual.device` and virtual `IOHIDUserDevice` creation fails. Regenerate the profile after adding the Mac, then `./Scripts/ojd signing install-profiles`.

Regenerate profiles after changing capabilities. Xcode may otherwise reuse a stale profile. When the development DEXT profile has `transport.usb`, it must contain exactly the seven approved Microsoft pairs; a wildcard or a GameSir dictionary is a mismatch and the signing gate rejects it. The connected GameSir G7 SE (`3537:1010`) uses the app's direct IOUSBHost route and does not require a DriverKit grant.

Normally, invoke the desired signed operation and follow its prompts:

```bash
./Scripts/ojd build install dev
```

The command searches supported local profile locations, installs discovered profiles, configures matching Keychain identities, and resumes. Use these commands only when automatic repair reports an asset mismatch:

```bash
./Scripts/ojd signing audit
./Scripts/ojd signing configure
./Scripts/ojd signing doctor
```

The doctor fails closed if the DEXT profile is missing while the host can use it, a required entitlement is absent, the USB entitlement (when present) has the wrong shape, or forbidden entitlements are present. A DEXT profile without `transport.usb` is reported as skipped, not failed.

## Developer ID / Distribution

The Developer ID profiles are installed separately as `OpenJoystickDriver_DevID.provisionprofile` and `OpenJoystickDriver_VirtualHIDDevice_DevID.provisionprofile`. GitHub Actions consumes the latter from `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`; development profiles and Apple Development identities never enter the release job.

USB and PCI DEXT distribution export is the exception to Xcode's normal automatic flow. For every distribution environment:

1. Build the final DEXT.
1. Generate and download separate app and DEXT profiles for that environment.
1. Rename the DEXT profile to `embedded.provisionprofile` and replace the profile inside the built DEXT.
1. Re-sign the DEXT with the distribution identity, timestamp, hardened runtime, and the production canonical entitlement plist.
1. Configure the app archive for manual signing with its separate app profile.
1. Embed the already signed DEXT using the System Extensions copy phase.
1. Archive and export for the same environment.
1. Compare the signed entitlements of both code items with their decoded profiles exactly.

Representative DEXT signing command:

```bash
codesign -s "Developer ID Application: ..." -f --timestamp -o runtime \
  --entitlements Sources/DriverKitGenerator/Entitlements/VirtualHIDDevice.entitlements \
  /path/to/com.openjoystickdriver.VirtualHIDDevice.dext
```

Do not change the provisioning profile to silence an entitlement mismatch. Kevin's guide notes that these failures normally mean the signing entitlement plist does not exactly match the selected profile. Inspect Organizer's distribution log and the archived signing configuration.

## Verification

```bash
./Scripts/ojd check driverkit
./Scripts/ojd signing doctor
codesign -d --entitlements - --xml /path/to/OpenJoystickDriver.app
extensions=/path/to/OpenJoystickDriver.app/Contents/Library/SystemExtensions
codesign -d --entitlements - --xml "$extensions/com.openjoystickdriver.VirtualHIDDevice.dext"
security cms -D -i /path/to/profile.provisionprofile
```

When the DEXT has `transport.usb`, verify the seven Microsoft product IDs and no wildcard. Verify the host allowlist is exactly `com.openjoystickdriver.VirtualHIDDevice` and the DEXT has no virtual-HID entitlement.
