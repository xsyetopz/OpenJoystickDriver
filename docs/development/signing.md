# Signing assets

OpenJoystickDriver's application contains a DriverKit system extension and uses
restricted HID entitlements. Apple issues the certificates and provisioning
profiles through
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/).

## Who needs signing assets

### End user

Do not create certificates or provisioning profiles. Install a signed,
notarized OpenJoystickDriver release from the project publisher. Never accept a
publisher's private signing key or `.p12` file.

### Parser or controller-record contributor

No signing assets are required. `swift test` and
`./scripts/ojd diagnose record` cover the source and raw-USB paths documented in
`CONTRIBUTING.md`.

### Full-app developer

You must be a member of the Apple Developer Program team that owns both exact
App IDs:

- host application: `com.openjoystickdriver`;
- generated DriverKit extension: `com.openjoystickdriver.VirtualHIDDevice`.

App IDs are globally registered. Membership in a different Apple developer team
does not grant permission to generate profiles for these identifiers. A fork
would need its own configurable identifiers and matching entitlement approval;
the current build contract intentionally uses the publisher identifiers.

### Release publisher

Release signing additionally requires the publisher's Developer ID Application
identity, Developer ID provisioning, notarization credentials, and Sparkle
EdDSA keys. Do not distribute these secrets to contributors or end users.

## Development setup

### 1. Obtain entitlement access

The team's Account Holder must request or enable the capabilities before profile
creation. Apple documents DriverKit entitlement requests at
[Requesting Entitlements for DriverKit Development](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development)
and managed capability requests at
[Capability Requests](https://developer.apple.com/help/account/capabilities/capability-requests).

The host App ID must authorize:

| Entitlement | Portal capability or purpose |
| --- | --- |
| `com.apple.developer.system-extension.install` | System Extension |
| `com.apple.developer.driverkit.userclient-access` containing only `com.openjoystickdriver.VirtualHIDDevice` | Communicates with Drivers / exact DriverKit client allowlist |
| `com.apple.developer.hid.virtual.device` | Compatibility virtual HID device; request it as a managed capability if it is not available for the team |

The DriverKit App ID and its selected entitlement group must authorize exactly:

```text
com.apple.developer.driverkit
com.apple.developer.driverkit.family.hid.device
com.apple.developer.driverkit.transport.hid
com.apple.developer.driverkit.family.hid.eventservice
```

Do not enable `com.apple.developer.driverkit.allow-any-userclient-access`.
OpenJoystickDriver deliberately uses the host's exact user-client allowlist.

Apple ties approved DriverKit entitlements to the development team. If the
DriverKit App ID or entitlement group is unavailable in the portal, the Account
Holder must complete the request at
[Apple's system-extension entitlement page](https://developer.apple.com/system-extensions/)
or contact Apple Developer Support. Repository changes cannot grant the
entitlement.

### 2. Create an Apple Development identity

On the Mac that will build the app:

1. Open **Xcode > Settings > Accounts**.
2. Select the correct Apple Developer Program team.
3. Open **Manage Certificates** and create an **Apple Development** certificate.
4. In Keychain Access, confirm it appears under **My Certificates** with a
   private key nested beneath it.

Create the identity on the build Mac. A downloaded `.cer` does not contain the
private key required by `codesign`. Apple lists the certificate types in its
[certificate overview](https://developer.apple.com/help/account/create-certificates/certificates-overview).

Verify locally:

```bash
security find-identity -v -p codesigning
```

The output must include at least one valid `Apple Development` identity.

### 3. Create the two development profiles

An Account Holder or Admin creates these in **Certificates, Identifiers &
Profiles > Profiles**; a team member with access can then download them:

| Local filename | Portal profile type | App ID | Certificate/device |
| --- | --- | --- | --- |
| `OpenJoystickDriver.provisionprofile` | **Mac App Development** | `com.openjoystickdriver` | Select the Apple Development identity above and the target Mac |
| `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` | **DriverKit Development** | `com.openjoystickdriver.VirtualHIDDevice` | Select the same Apple Development identity, target Mac, and approved DriverKit entitlement group |

Apple's current profile workflow is documented in
[Create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)
and
[Create a DriverKit development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-driverkit-development-provisioning-profile).

Download the profiles, rename them to the exact local filenames above, and put
them in:

```text
~/Documents/Profiles/
```

The portal's profile display name may differ from the local filename. The
repository reads the embedded display name for `DEXT_BUILD_PROFILE`.

### 4. Install, configure, and verify

```bash
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd signing audit \
  "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
./scripts/ojd signing doctor
```

`signing configure` generates `.env.dev`. It matches the certificate embedded in
each profile to a Keychain identity, then reads the Team ID and profile name
from the profiles.

Then build and install:

```bash
./scripts/ojd rebuild dev
```

macOS must approve the system extension and the app's requested privacy access
before live relay and controller checks can pass.

## Where each development variable comes from

| Variable | Source |
| --- | --- |
| `CODESIGN_IDENTITY` | SHA-1 of the Apple Development identity whose certificate is embedded in the DriverKit development profile |
| `DEVELOPMENT_TEAM` | `TeamIdentifier` in the host development profile |
| `GUI_PROVISIONING_PROFILE` | Installed path of `OpenJoystickDriver.provisionprofile` |
| `DEXT_BUILD_PROFILE` | `Name` embedded in `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` |
| `OJD_USE_LEGACY_DRIVERKIT_PROFILE` | Generated as `1` only when the host development profile contains the known Apple-approved legacy user-client value |
| `OJD_USE_LOCAL_SWIFTERKIT` | Developer choice; leave `0` unless intentionally testing the sibling checkout |

The first five values are generated by `./scripts/ojd signing configure`.

## Replace legacy profile entitlements

Profiles created for older OpenJoystickDriver builds may still name
`com.openjoystickdriver.daemon` or grant allow-any DriverKit access. Do not edit
the downloaded profile. Apple signs it, so any local edit invalidates it.

While the corrected host capability request is pending, `signing configure`
recognizes this one approved legacy value:

```text
["com.openjoystickdriver.VirtualHIDDevice\ncom.openjoystickdriver.daemon"]
```

It writes `OJD_USE_LEGACY_DRIVERKIT_PROFILE=1` to `.env.dev`. Development
builds still embed that profile, but remove
`com.apple.developer.driverkit.userclient-access` from the generated
`.build/OpenJoystickDriver.entitlements` file. This is a permitted subset of
the profile entitlements, so the signed host does not request the malformed
value. `Sources/OpenJoystickDriver/App/Host.entitlements` remains the exact
single-relay policy. Release builds and CI reject this fallback.

The app and Compatibility `IOHIDUserDevice` output remain available in this
mode. DriverKit relay diagnostics are unavailable because the signed host has no
user-client grant. The generated DriverKit relay may still be embedded and
registered, but the host cannot open its user client until the corrected grant
is approved.

Remove the mode after Apple approves the corrected request: install the newly
generated host development profile and rerun `./scripts/ojd signing configure`.
The command writes the flag back to `0` when the profile contains only
`com.openjoystickdriver.VirtualHIDDevice`.

### Host App ID

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Select the App ID `com.openjoystickdriver`.
3. Open **Capability Requests**.
4. Submit a replacement **DriverKit UserClient Access** request containing one
   bundle ID entry:

   ```text
   com.openjoystickdriver.VirtualHIDDevice
   ```

   Do not include `com.openjoystickdriver.daemon`. Do not paste several bundle
   IDs into one field separated by newlines. The entitlement must be an array
   with one string element.
5. If the portal refuses a replacement because an older request is still
   active, contact Apple Developer Support. Ask them to remove the existing
   DriverKit UserClient Access grant and replace it with the single bundle ID
   above. Include the existing capability request ID.
6. After approval, open the App ID's **Capabilities** tab and confirm DriverKit
   UserClient Access is enabled.

Regenerate both host profiles after the App ID changes:

- **Mac App Development** to `OpenJoystickDriver.provisionprofile`;
- **Developer ID** to `OpenJoystickDriver_DevID.provisionprofile`.

Select the installed certificate of the corresponding type when generating
each profile.

### DriverKit App ID

1. Select `com.openjoystickdriver.VirtualHIDDevice` under **Identifiers**.
2. Disable **DriverKit Allow Any UserClient Access** and its development
   variant if either is enabled.
3. Keep the base DriverKit and required HID family capabilities enabled.
4. If allow-any belongs to an Apple-assigned DriverKit entitlement group rather
   than a visible toggle, request a replacement group without
   `com.apple.developer.driverkit.allow-any-userclient-access`.
5. Create a new **DriverKit Development** profile. Select the entitlement group
   that contains the required HID entitlements and does not contain allow-any.
6. Download it as
   `OpenJoystickDriver_VirtualHIDDevice.provisionprofile`.

The host and dext belong to the same team. The dext does not need allow-any
access. The host profile names the one dext it can open.

Replace the files under `~/Documents/Profiles/`, then run:

```bash
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd signing doctor
```

The doctor must report this host value:

```text
com.apple.developer.driverkit.userclient-access =
  ["com.openjoystickdriver.VirtualHIDDevice"]
```

The DriverKit profile must not contain
`com.apple.developer.driverkit.allow-any-userclient-access`.

## Publisher release assets

The Account Holder creates a **Developer ID Application** certificate from
[Apple's Developer ID certificate page](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).
It must be installed with its private key. A Developer ID Installer certificate
is not used because OpenJoystickDriver distributes an application/DMG, not a
signed installer package.

Create or regenerate the Developer ID provisioning profile for
`com.openjoystickdriver`, selecting that Developer ID Application certificate
and the host capabilities listed above. Download it as:

```text
~/Documents/Profiles/OpenJoystickDriver_DevID.provisionprofile
```

When that optional profile is present, `signing install-profiles` installs it
and `signing configure` writes `.env.release`. Without it, development setup
still succeeds and release configuration is skipped explicitly.

Notarization should use a Keychain profile rather than a plaintext password:

```bash
xcrun notarytool store-credentials "openjoystickdriver-notary" \
  --apple-id "PUBLISHER_ACCOUNT" \
  --team-id "TEAM_ID"
```

Set `NOTARIZE_KEYCHAIN_PROFILE` to `openjoystickdriver-notary`. Apple documents
this flow in
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Sparkle's `bin/generate_keys` creates the publisher EdDSA key pair. Keep the
private key private; place the printed public key in `SPARKLE_PUBLIC_ED_KEY` and
the release automation's private-key representation in
`SPARKLE_ED_PRIVATE_KEY`. See
[Sparkle's EdDSA documentation](https://sparkle-project.org/documentation/).

A dev-signed dext does not prove that the Developer ID build can be distributed
or notarized. Apple requires a distribution profile for the release target.

## Safe diagnostics

These commands omit private values from their normal output:

```bash
./scripts/ojd env audit
./scripts/ojd signing audit \
  "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
./scripts/ojd signing doctor
```

Never commit `.env.dev`, `.env.release`, certificates, provisioning profiles,
notarization passwords, `.p12` files, or Sparkle private keys.
