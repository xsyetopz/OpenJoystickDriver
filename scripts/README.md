# Repository Commands

This directory has one supported command entry point: `./scripts/ojd`.
Implementation files are grouped by ownership and are not standalone command
surfaces.

## Layout

| Path | Responsibility |
| --- | --- |
| `scripts/ojd` | Stable command dispatcher and help |
| `scripts/build-tools/` | Application, DriverKit, and bundle construction |
| `scripts/catalog/` | Controller-source import and record validation |
| `scripts/diagnostics/` | Runtime probes, focused launch helpers, and repairs |
| `scripts/docs/` | Archived external-evidence refresh |
| `scripts/shared/` | Shared shell environment, signing, and libusb helpers |
| `scripts/quality/` | Repository validators and compatibility test harnesses |
| `scripts/release/` | Versioning, notarization, appcast, and DMG packaging |
| `scripts/signing/` | Local and CI signing setup |

Run implementation behavior through `./scripts/ojd`; paths below these ownership
directories may change. Validate routing, file modes, and shell syntax with:

```bash
./scripts/ojd validate scripts
```

## Implementation Inventory

All implementation paths are internal to the dispatcher.

| File | Invoked by | Inputs and effects | Validation |
| --- | --- | --- | --- |
| `README.md` | Documentation links | Documents the supported command surface | Link and stale-path checks |
| `ojd` | Developers and CI | Dispatches commands; fixed routes reject extra arguments | CLI and script-layout tests |
| `build-tools/build.sh` | `build`, `rebuild`, `rebuild-fast`, `lint` | Writes `.build/`; rebuild routes replace installed components | Swift packaging contracts; shell syntax |
| `build-tools/bundles.sh` | Build implementation | Constructs and signs the application and DriverKit bundles | Swift packaging contracts; shell syntax |
| `catalog/generate-controller-catalog.py` | `catalog regenerate` | Reads locked sources; check is read-only, write replaces generated records | Catalog unit tests and regeneration check |
| `catalog/generate-xpad-records.py` | `catalog xpad` | Reads local or GitHub Linux source and writes review output | xpad unit tests |
| `catalog/validate-profiles.py` | `validate profiles` and catalog generator | Reads and validates controller records | Catalog unit tests and profile gate |
| `diagnostics/catalina-smoke.sh` | `diagnose catalina` | Verifies the foreground app bundle and absence of helper agents | Shell syntax; macOS 10.15 manual check |
| `diagnostics/diagnose.sh` | `diagnose` routes | Reads system/runtime state; backend probes can change temporary runtime output settings | Help routing; shell syntax; local diagnostics |
| `diagnostics/launch-sdl-gamecontroller.sh` | `launch sdl-gamecontroller` | Selects a compatibility route and launches the requested app | Shell syntax; manual SDL check |
| `diagnostics/repair-stale-dext.sh` | `repair stale-dext` | Finds and terminates stale DriverKit processes | Shell syntax; focused local repair |
| `docs/export-external-issues.py` | `docs export-external-issues` | Reads GitHub through `gh` and replaces archived issue evidence | Path validation; explicit manual refresh |
| `shared/common.sh` | Build, diagnostics, notarization, and packaging implementations | Loads one root environment file; may build cached universal libusb artifacts | Environment and packaging tests; shell syntax |
| `quality/env-audit.py` | `env audit` | Reads environment-file keys without printing values | Environment contract tests |
| `quality/test-parsers-macos14.sh` | `test parsers-macos14` | Creates isolated harness and cache directories under `/tmp` | Parser harness gate |
| `quality/validate-scripts.py` | `validate scripts` | Reads repository paths and runs `bash -n` | Script-layout unit tests and CI |
| `quality/validate-swift-structure.py` | `validate swift-structure` | Reads Swift paths, sizes, names, and directives | Structural unit tests and CI |
| `release/bump-version.sh` | `bump-version` | Updates version references after verifying a changelog heading | Swift packaging contracts and diff review |
| `release/dmg-background.py` | Release package implementation | Writes a deterministic PNG to the requested path | Packaging contract |
| `release/notarize.sh` | `notarize` and release packaging | Uses Apple notarization services, writes submission state, and staples the app | Help and shell checks; release-only CI |
| `release/package.sh` | `package release`, `package appcast` | Builds signed artifacts, mounts temporary DMGs, notarizes, and writes release output | Swift packaging contracts; release-only CI |
| `signing/configure.py` | Signing implementation | Reads profiles and Keychain identities; writes root environment files | Environment contracts; focused local setup |
| `signing/export-github-secrets.sh` | `signing export-github-secrets` | Reads signing material, writes private build output, optionally updates GitHub secrets | Shell syntax; explicit operator action |
| `signing/signing.sh` | `signing` routes | Audits or installs profiles, imports identities, creates CI Keychain state, or configures environment files | Help and shell checks; release CI and local setup |

## Task Map

| Goal | Command | Notes |
| --- | --- | --- |
| Install profiles | `./scripts/ojd signing install-profiles` | Copies from `~/Documents/Profiles/` |
| Check installed profiles | `./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile` | Safe output; no identifiers |
| Generate `.env.dev` + `.env.release` | `./scripts/ojd signing configure` | Re-run after cert/profile changes |
| Diagnose signing mismatches | `./scripts/ojd signing doctor` | Use before tweaking Xcode settings |
| Build signed dev app | `./scripts/ojd build dev` | Output to `.build/` |
| Install signed dev build | `./scripts/ojd rebuild dev` | Application and dext; the app embeds its service registration |
| Fast rebuild (app only) | `./scripts/ojd rebuild-fast dev` | Skip dext upgrade |
| Package release DMG | `./scripts/ojd package release <version>` | Builds, notarizes, staples |
| Run script unit tests | `./scripts/ojd test scripts` | Covers catalog, routing, layout, and environment contracts |

## Initial Setup (Per Machine / Team)

### 1. Provisioning profiles

The scripts look for provisioning profiles at:

- `~/Library/MobileDevice/Provisioning Profiles/`

Install (copies from `~/Documents/Profiles/` or `~/Documents/profiles/`):

```bash
./scripts/ojd signing install-profiles
```

Expected filenames:

- `OpenJoystickDriver.provisionprofile` (GUI, Apple Development)
- `OpenJoystickDriver_DevID.provisionprofile` (GUI, Developer ID)
- `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` (DriverKit dext, Apple Development)

Sanity-check what you installed (safe output; no identifiers printed):

```bash
./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
```

### 2. Keychain identities

You should see at least:

- `Apple Development: …`
- `Developer ID Application: …`

```bash
security find-identity -v -p codesigning
```

The Team ID in your provisioning profiles must match the Team ID encoded in your certificate **Subject OU**.
You must not trust the `(...)` suffix in the Keychain display name as the Team ID.

If `security find-identity` shows **0 valid identities**, you are usually missing Apple intermediate CA
certificates (WWDR / Developer ID). Apple publishes them here:

- <https://www.apple.com/certificateauthority/>

### 3. Generate root `.env.dev` and `.env.release`

These are the only local environment files loaded. See `../docs/development/environment.md`; run `./scripts/ojd env audit` to validate names without printing values.

This repo reads your Keychain + installed profiles and writes both env files:

```bash
./scripts/ojd signing configure
```

Re-run this after rotating certificates, regenerating profiles, or switching teams.

## Common Tasks

### Application service install / restart

On macOS 13 and newer, `SMAppService.mainApp` registers the main app as a login item.
The app contains no LaunchAgent or helper executable. On macOS 10.15 through 12,
run the app directly; automatic login registration is unavailable.

Commands (run the app-bundled binary):

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless install
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless uninstall
```

### Dev build (signed) + app bundle

```bash
./scripts/ojd build dev
```

### Build the DriverKit system extension (.dext)

```bash
./scripts/ojd build dext
```

If DriverKit build fails due to certificate matching, see the Troubleshooting section below.

## Notarization

Store notarization credentials in the macOS Keychain:

```bash
OJD_ENV=release ./scripts/ojd notarize store-credentials OJDNotary
```

Put these into `.env.release`:

- `NOTARIZE_KEYCHAIN_PROFILE` (the notarytool Keychain profile name)

Then:

```bash
OJD_ENV=release ./scripts/ojd rebuild release
OJD_ENV=release ./scripts/ojd notarize submit
OJD_ENV=release ./scripts/ojd notarize status
```

### Release package

For a release build that does not install anything on the build machine:

```bash
./scripts/ojd package release 0.5.0-alpha.5
```

This command uses release signing, embeds the DriverKit extension into the app
bundle, submits the app for notarization, staples the accepted ticket, verifies
the result, and writes a drag-and-drop DMG containing `OpenJoystickDriver.app`
and an `Applications` symlink:

```text
.build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg
```

The package command does not register a login item and does not submit a
system-extension activation request on the build machine. Testers still need to
install and approve the app/system extension locally.

## GitHub Actions release

`.github/workflows/release.yml` runs on SemVer tags such as `0.1.0` or
`0.5.0-alpha.5` and by manual dispatch.
It installs `libusb`, validates profiles, imports signing material, builds a
release app, notarizes it, uploads the release DMG as a workflow artifact, and
publishes the GitHub Release.

### Required repository secrets

- `APPLE_DEVELOPMENT_CERT_BASE64`
- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `CERTIFICATE_SECRET`
- `KEYCHAIN_SECRET`
- `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_PASSWORD`

The certificate payload secrets are base64-encoded certificate export files.
The profile secrets are base64-encoded `.provisionprofile` files.

### Generate GitHub secrets locally

To collect all release secrets in one local step:

```bash
./scripts/ojd signing export-github-secrets --repo xsyetopz/OpenJoystickDriver
```

If identity export paths are not supplied, the script exports signing identities
from your login keychain into the private output directory. Keychain may prompt
for permission. The script reads the two installed release provisioning
profiles, prompts for the identity export password and notarization credentials,
generates a temporary CI keychain password, then writes:

```text
.build/github-actions-secrets/
  values/*.txt
  apply-github-secrets.sh
```

To import them into GitHub with `gh`:

```bash
.build/github-actions-secrets/apply-github-secrets.sh --repo xsyetopz/OpenJoystickDriver
```

Or do both steps in one command:

```bash
./scripts/ojd signing export-github-secrets --repo xsyetopz/OpenJoystickDriver --apply
```

Keep `.build/github-actions-secrets/` private. It contains raw secret values.

If you already exported separate signing identity files from Keychain Access,
pass them explicitly with `--apple-development-identity` and
`--developer-id-identity`.

## Troubleshooting

<details>
<summary>Keychain Access shows certs, but <code>security find-identity</code> prints 0 identities</summary>

If the Keychain UI shows certs + private keys but `security find-identity` prints
`0 valid identities found`, your keychain file permissions are wrong.

Fix:

```bash
chmod 700 "$HOME/Library/Keychains"
chmod 600 "$HOME/Library/Keychains/login.keychain-db"
```

Then log out/in (or reboot) and try again.

</details>

<details>
<summary>Team/certificate mismatch (most common)</summary>

If you have a `Developer ID Application` cert for one team but your `Apple Development`
cert is for a different team, `xcodebuild` will fail with:

- “Provisioning profile … doesn’t include signing certificate …”
- “No certificate for team … matching …”

Commands to see what you have (prints only Team IDs):

```bash
# Team ID in your Apple Development .cer (from ~/Documents/Certificates)
# NOTE: the Team ID is the certificate Subject OU (not the display-name (...) suffix).
openssl x509 -inform DER -in "$HOME/Documents/Certificates/development.cer" -noout -subject -nameopt RFC2253 \
  | sed -nE 's/.*OU=([^,]+).*/\\1/p'

# Team ID inside the DriverKit provisioning profile
openssl smime -inform der -verify -noverify \
  -in "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile" 2>/dev/null \
  | plutil -extract TeamIdentifier.0 raw -o - -
```

If those Team IDs differ:

1. Create an **Apple Development** certificate for the **same team** as the provisioning profiles.
2. Import the downloaded `.cer` into Keychain Access (it must include a private key).
3. Regenerate the Apple Development provisioning profiles (application and dext) selecting that certificate.
4. Reinstall profiles: `./scripts/ojd signing install-profiles`
5. Re-generate env files: `./scripts/ojd signing configure`

Entitlement note for `com.apple.developer.hid.virtual.device`:

- It must be present on the identifier that creates the user-space virtual device (IOHIDUserDevice).
- In this repo it belongs to the main application executable.
- The DriverKit `.dext` does not use IOHIDUserDevice and does not need this entitlement.

</details>

<details>
<summary>DriverKit build fails with “No certificate for team … matching …”</summary>

If you see an error like:

```text
No certificate for team '9PQP6CDMQT' matching 'Apple Development: … (XXXXXXXXXX)' found
```

This is often caused by Xcode matching based on the certificate display name suffix `(...)`.

Fix:

1. Re-run `./scripts/ojd signing configure` so `CODESIGN_IDENTITY` is a SHA1 fingerprint.
2. Re-run `./scripts/ojd build dext` (this prefers SHA1 for `xcodebuild`).

</details>
