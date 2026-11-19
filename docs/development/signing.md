# Signing the App and XboxUSBDevice DEXT

macOS runs OJD only when Apple's signature and a permission slip, called a provisioning profile, match each other. Think of the signature as an ID card and the profile as a guest list: macOS checks that the name on the card is on the list. OJD has two pieces of code, and each gets its own profile:

- host app: `com.openjoystickdriver`
- DriverKit extension (DEXT): `com.openjoystickdriver.XboxUSBDevice` (XboxUSB personality only)

Follow [Kevin Elliott's DEXT signing guide](https://developer.apple.com/forums/thread/809202). Apple fills in the DriverKit entitlement values for each team, so never guess, widen, or patch a profile in source.

## Which Entitlements Go Where

An entitlement is one permission written into a profile. The host app needs:

- `com.apple.developer.system-extension.install = true`
- `com.apple.developer.driverkit.userclient-access` in the host profile. It's a list of bundle IDs that includes the DEXT and may name others, such as `com.openjoystickdriver.VirtualHIDDevice`. `Host.entitlements` asks for exactly the DEXT
- `com.apple.developer.hid.virtual.device = true` (for `IOHIDUserDevice` gamepads)
- its profile's application and team IDs

Never put `com.apple.developer.driverkit.allow-any-userclient-access` in the host list, because it lets any app talk to the driver.

The DEXT profile needs exactly `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb`. Both development and Developer ID use this limited USB list:

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

In hexadecimal the pairs are `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`. The build stops when:

- the DEXT profile has any other USB entitlement
- a DEXT profile or signed DEXT holds the virtual-device entitlement (Apple allows it in the app profile only)
- a DEXT profile or signed DEXT holds the HID family, transport, or event-service entitlements

Apple has given the team the `transport.usb` capability (VendorID and ProductID). Turn it on for the DEXT App ID and make a fresh DriverKit profile.

| Build | Host profile `userclient-access` | What happens |
| --- | --- | --- |
| Development | missing, or names only other bundle IDs | The app is signed without it and no extension goes inside. Nothing shows under System Settings > General > Login Items & Extensions > Driver Extensions, and OJD can't take over Xbox USB controllers. Virtual gamepads still work. |
| Release, Developer ID | must include the DEXT | Apple grants it per team and per DEXT bundle ID. [Ask for it](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development), then make fresh host profiles. A grant for another bundle ID builds no DEXT. |

The DEXT entitlements come from `Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements`.

## Development Profiles

Apple Development signing uses one profile for the app and one for the DEXT. Default paths:

```text
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile
~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_XboxUSBDevice.provisionprofile
```

`signing configure` writes these paths to `GUI_PROVISIONING_PROFILE` and `DEXT_PROVISIONING_PROFILE` in `.env.dev`. It also writes `CODESIGN_IDENTITY`: the SHA-1 of the Apple Development identity that both profiles contain, which signs the app and the DEXT.

Xcode finds the DEXT profile by its `Name`. If more than one identity fits, `signing configure --development-identity <sha1>` (or `--release-identity <sha1>` for Developer ID) picks one. Without it, OJD takes the lowest SHA-1.

The host development profile has a list of allowed Macs, and this Mac must be on it. If it isn't, AMFI ignores the virtual-device entitlement and making an IOHIDUserDevice fails. After you add the Mac, make a fresh profile and run `just signing-install-profiles`. Make a fresh profile after any capability change too, or Xcode may keep using the out-of-date one.

The signing check refuses a wildcard or a GameSir entry in a development DEXT profile. The GameSir G7 SE (`3537:1010`) goes through the app's direct IOUSBHost road and needs no DriverKit grant.

This command finds, installs, and sets up the profiles and the matching Keychain identities, and asks you questions when it needs to:

```bash
just install-dev
```

Run these only when the automatic repair reports that the files don't match:

```bash
just signing-audit
just signing-configure
```

`configure` picks a Keychain identity that has a private key and whose SHA1 is inside both profiles of one kind. With several, it takes the lowest SHA1 and prints it. With none, it fails and lists each profile's SHA1s next to the Keychain's SHA1s. It never writes an identity the Keychain can't sign with. `signing profile-info` lists every certificate inside a profile, and `signing import-embedded` imports them all.

## Developer ID / Distribution

Install the Developer ID profiles as `OpenJoystickDriver_DevID.provisionprofile` and `OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile`. GitHub Actions reads the second one from `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`. Development profiles and identities stay out of the release job.

Xcode's automatic export skips USB and PCI DEXTs, so do these steps by hand for each environment:

1. Build the final DEXT, and download the app profile and the DEXT profile.
2. Rename the DEXT profile to `embedded.provisionprofile` and swap it in for the one inside the DEXT.
3. Sign the DEXT again with the distribution identity, a timestamp, the hardened runtime, and the production entitlement plist.
4. Set the app archive to manual signing with its app profile.
5. Put the signed DEXT inside with the System Extensions copy phase.
6. Archive and export.
7. Check that the signed entitlements of the app and the DEXT match their decoded profiles.

DEXT signing command:

```bash
codesign -s "Developer ID Application: ..." -f --timestamp -o runtime \
  --entitlements Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements \
  /path/to/com.openjoystickdriver.XboxUSBDevice.dext
```

Never change the profile to hide an entitlement mismatch. Usually it's the signing plist that differs from the profile. Read Organizer's distribution log and the signing settings saved in the archive.

## Check the Result

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
