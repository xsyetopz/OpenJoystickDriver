# Signing the App and XboxUSBDevice DEXT

Two code items, each provisioned separately:

- host app: `com.openjoystickdriver`
- DriverKit extension: `com.openjoystickdriver.XboxUSBDevice` (XboxUSB personality only)

Follow [Kevin Elliott's DEXT signing guide](https://developer.apple.com/forums/thread/809202). DriverKit entitlement values are customized provisioning data; never infer, broaden, or repair a profile in source.

## Entitlement Ownership

The host app requires:

- `com.apple.developer.system-extension.install = true`
- `com.apple.developer.driverkit.userclient-access` in the host profile: a bundle ID list that includes the DEXT and may name others, such as `com.openjoystickdriver.VirtualHIDDevice`. `Host.entitlements` claims exactly the DEXT
- `com.apple.developer.hid.virtual.device = true` (for `IOHIDUserDevice` gamepads)
- its profile's application and team identifiers

Never put `com.apple.developer.driverkit.allow-any-userclient-access` in the host allowlist.

The DEXT profile requires exactly `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb`, with this restricted USB value for development and Developer ID:

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

The pairs are `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`. The build rejects a DEXT profile with other USB entitlements, and a profile or signed DEXT holding the virtual-device entitlement (Apple: app profile only) or the HID family, transport, or event-service entitlements.

The team's `transport.usb` capability (VendorID and ProductID) is assigned; enable it on the DEXT App ID and regenerate the DriverKit profile.

| Build | Host profile `userclient-access` | Result |
| --- | --- | --- |
| Development | missing, or names only other bundle IDs | The app is signed without it, no extension is embedded, nothing appears under System Settings > General > Login Items & Extensions > Driver Extensions, and Xbox USB ownership is unavailable. Virtual gamepads still work. |
| Release, Developer ID | must include the DEXT | Apple grants it per team and DEXT bundle ID; [request it](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development), then regenerate the host profiles. Another bundle ID's grant builds no DEXT. |

DEXT entitlement input: `Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements`.

## Development Profiles

Apple Development signing uses separate app and DEXT profiles. Default paths:

```text
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_XboxUSBDevice.provisionprofile
```

`signing configure` writes these paths to `GUI_PROVISIONING_PROFILE` and `DEXT_PROVISIONING_PROFILE` in `.env.dev`, and the SHA-1 of the Apple Development identity both profiles embed to `CODESIGN_IDENTITY` (signs app and DEXT).

The DEXT profile's `Name` is Xcode's profile specifier. `signing configure --development-identity <sha1>` (`--release-identity <sha1>` for Developer ID) picks among qualifying identities; default is the lowest SHA-1.

The host development profile's device list must include this Mac, or AMFI ignores the virtual-device entitlement and IOHIDUserDevice creation fails. After adding the Mac, regenerate the profile and run `just signing-install-profiles`. Regenerate after any capability change, or Xcode may reuse a stale profile.

The signing gate rejects a wildcard or GameSir dictionary in a development DEXT profile. The GameSir G7 SE (`3537:1010`) uses the app's direct IOUSBHost route, with no DriverKit grant.

It finds, installs, and configures profiles and matching Keychain identities, prompting as needed:

```bash
just install-dev
```

Run these only after automatic repair reports an asset mismatch:

```bash
just signing-audit
just signing-configure
```

`configure` picks a Keychain identity with a private key whose SHA1 is embedded in both profiles of a kind (lowest SHA1 if several, printed). With none it fails, listing each profile's embedded SHA1s beside the Keychain SHA1s. It never writes an identity the Keychain cannot sign with. `signing profile-info` lists every embedded certificate; `signing import-embedded` imports them all.

## Developer ID / Distribution

Install Developer ID profiles as `OpenJoystickDriver_DevID.provisionprofile` and `OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile`; GitHub Actions reads the latter from `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`. Development profiles and identities stay out of the release job.

Xcode's automatic export skips USB and PCI DEXT distribution. Per environment:

1. Build the final DEXT; download separate app and DEXT profiles.
2. Rename the DEXT profile to `embedded.provisionprofile` and replace the one inside the DEXT.
3. Re-sign the DEXT with the distribution identity, timestamp, hardened runtime, and production canonical entitlement plist.
4. Set the app archive to manual signing with its app profile.
5. Embed the signed DEXT with the System Extensions copy phase.
6. Archive and export.
7. Compare both code items' signed entitlements with their decoded profiles.

DEXT signing command:

```bash
codesign -s "Developer ID Application: ..." -f --timestamp -o runtime \
  --entitlements Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements \
  /path/to/com.openjoystickdriver.XboxUSBDevice.dext
```

Never change the profile to silence an entitlement mismatch; the signing plist usually differs from the profile. Inspect Organizer's distribution log and the archived signing configuration.

## Verification

```bash
just driverkit-check
just signing-audit
codesign -d --entitlements - --xml /path/to/OpenJoystickDriver.app
extensions=/path/to/OpenJoystickDriver.app/Contents/Library/SystemExtensions
codesign -d --entitlements - --xml "$extensions/com.openjoystickdriver.XboxUSBDevice.dext"
security cms -D -i /path/to/profile.provisionprofile
```

## Further Reading

- [Environment Files](environment.md)
- [Tester Builds](tester-builds.md)
