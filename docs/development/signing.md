# Signing the app and XboxUSBDevice DEXT

OpenJoystickDriver has two independently provisioned code items:

- host app: `com.openjoystickdriver`
- USB DriverKit extension: `com.openjoystickdriver.XboxUSBDevice`

Follow [Kevin Elliott's DEXT signing guide](https://developer.apple.com/forums/thread/809202).
DriverKit entitlement values are customized provisioning data; do not infer, broaden, or repair a
profile in source.

## Entitlement ownership

The host app requires:

- `com.apple.developer.system-extension.install = true`
- `com.apple.developer.driverkit.userclient-access = ["com.openjoystickdriver.XboxUSBDevice"]`
- `com.apple.developer.hid.virtual.device = true`
- its profile's application and team identifiers

The host allowlist must never use `com.apple.developer.driverkit.allow-any-userclient-access`.

The DEXT always requires `com.apple.developer.driverkit = true`. Development and Developer ID
signing use the same Apple-issued restricted USB value:

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

These are `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`,
`045E:0B0A`, and `045E:0B12`. The USB DEXT must not contain CoreHID's virtual-device entitlement or
any HIDDriverKit family/transport entitlement.

The canonical authored DEXT entitlement input is
`Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements`.

## Development profiles

Use Apple Development signing and separate profiles for the app and DEXT. The default local paths
are:

```text
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_XboxUSBDevice.provisionprofile
```

Regenerate profiles after changing capabilities. Xcode may otherwise reuse a stale profile. The
development DEXT profile must contain exactly the seven approved Microsoft pairs; a wildcard or a
GameSir dictionary is a mismatch and the signing gate rejects it. The connected GameSir G7 SE
(`3537:1010`) uses the app's direct IOUSBHost route and does not require a DriverKit grant.

Run:

```bash
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd signing doctor
./scripts/ojd build install dev
```

The doctor fails closed if the DEXT profile is missing, the host allowlist names the deleted
`VirtualHIDDevice` configuration, the USB entitlement shape differs, or forbidden entitlements are
present.

## Developer ID / distribution

The Developer ID profiles are installed separately as
`OpenJoystickDriver_DevID.provisionprofile` and
`OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile`. GitHub Actions consumes the latter from
`OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`; development profiles and Apple Development
identities never enter the release job.

USB and PCI DEXT distribution export is the exception to Xcode's normal automatic flow. For every
distribution environment:

1. Build the final DEXT.
2. Generate and download separate app and DEXT profiles for that environment.
3. Rename the DEXT profile to `embedded.provisionprofile` and replace the profile inside the built
   DEXT.
4. Re-sign the DEXT with the distribution identity, timestamp, hardened runtime, and the production
   canonical entitlement plist.
5. Configure the app archive for manual signing with its separate app profile.
6. Embed the already signed DEXT using the System Extensions copy phase.
7. Archive and export for the same environment.
8. Compare the signed entitlements of both code items with their decoded profiles exactly.

Representative DEXT signing command:

```bash
codesign -s "Developer ID Application: …" -f --timestamp -o runtime \
  --entitlements Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements \
  /path/to/com.openjoystickdriver.XboxUSBDevice.dext
```

Do not change the provisioning profile to silence an entitlement mismatch. Kevin's guide notes that
these failures normally mean the signing entitlement plist does not exactly match the selected
profile. Inspect Organizer's distribution log and the archived signing configuration.

## Verification

```bash
./scripts/ojd check driverkit
./scripts/ojd signing doctor
codesign -d --entitlements - --xml /path/to/OpenJoystickDriver.app
codesign -d --entitlements - --xml \
  /path/to/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext
security cms -D -i /path/to/profile.provisionprofile
```

For both development and production artifacts, verify the seven Microsoft product IDs and confirm
the wildcard is absent. Verify the host allowlist contains only
`com.openjoystickdriver.XboxUSBDevice` and the DEXT has no virtual-HID entitlement.
