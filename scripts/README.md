# Repository commands

OpenJoystickDriver has two supported command interfaces:

- the installed `OpenJoystickDriver` CLI for user control and diagnostics
- `./scripts/ojd` for repository development, validation, installation, and release tasks

Run `./scripts/ojd help` to see the repository commands. Its plain, non-color
output is keyboard-readable. `OpenJoystickDriverHIDTool` is internal and reserved
for focused hardware investigation. Files below `scripts/` are not standalone
commands. The `justfile` only delegates convenience commands to `./scripts/ojd`.

The main repository routes are `build install dev|release`, `build install-fast
dev`, `package tester`, `release bump-version`, `release package [version]`,
`release install-local [version]`, and `release notarize ...`. The legacy `rebuild`, `rebuild-fast`,
`bump-version`, `package release`, and `notarize` routes remain compatibility
aliases.

## Layout

| Path | Responsibility |
| --- | --- |
| `scripts/ojd` | Stable command dispatcher and help |
| `scripts/build-tools/` | Application, generated USB DriverKit extension, and bundle construction |
| `scripts/catalog/` | Controller-source import and record validation |
| `scripts/diagnostics/` | Runtime probes, focused launch helpers, and repairs |
| `scripts/docs/` | Archived external-evidence refresh |
| `scripts/platform/` | macOS toolchain, environment, signing, and packaging contract |
| `scripts/quality/` | Repository validators and compatibility test harnesses |
| `scripts/release/` | Versioning, notarization, and DMG packaging |
| `scripts/signing/` | Local and CI signing setup |

Run implementation behavior through `./scripts/ojd`; paths below these ownership
directories may change. Validate routing, file modes, and shell syntax with:

```bash
./scripts/ojd check scripts
```

## Implementation inventory

All implementation paths are internal to the dispatcher.

### Retained shell categories

Shell remains only where its process model is part of the interface or is
clearer than a translation: sourceable environment setup; sourced build,
DriverKit, signing, and notarization function libraries; tightly shell-native
diagnostic pipelines and temporary harness traps; and direct `exec` wrappers
that establish interactive or process environment state. Metadata generation,
filesystem manipulation, validation, and distribution orchestration use the
Python standard library instead. Concretely, `platform/environment.sh` remains
sourceable; `build-tools/*.sh` and `signing/signing.sh` remain shell function
libraries for toolchain/keychain operations; `diagnostics/diagnose.sh` and
`quality/test-parsers-macos14.sh` retain background-process, pipeline, and
heredoc harness semantics; and `diagnostics/sdl/gamecontroller.sh`,
`signing/export-github-secrets.sh`, and `release/notarize.sh` retain direct
environment/CLI wrappers. The migrated Python routes do not retain shell
compatibility shims.

| File | Invoked by | Inputs and effects | Validation |
| --- | --- | --- | --- |
| `README.md` | Documentation links | Documents the supported command surface | Link and stale-path checks |
| `ojd` | Developers and CI | Dispatches commands; fixed routes reject extra arguments | CLI and script-layout tests |
| `build-tools/build.sh` | `build`, `build install`, `build install-fast`, `lint` | Writes `.build/`; install routes replace installed components | Swift packaging contracts; shell syntax |
| `build-tools/bundles.sh` | Build implementation | Constructs and signs the application bundle | Swift packaging contracts; shell syntax |
| `build-tools/driverkit.sh` | `driverkit`, `build dext`, and install implementation | Generates, validates, builds, signs, and embeds the SwifterKit USB DriverKit extension | Deterministic generation, metadata/entitlement checks, unsigned native build, shell syntax |
| `catalog/generate-controller-catalog.py` | `catalog regenerate` | Reads locked sources; check is read-only, write replaces generated records | Catalog unit tests and regeneration check |
| `catalog/generate-xpad-records.py` | `catalog xpad` | Reads local or GitHub Linux source and writes review output | xpad unit tests |
| `catalog/validate-profiles.py` | `check profiles` and catalog generator | Reads and validates controller records | Catalog unit tests and profile gate |
| `diagnostics/catalina_smoke.py` | `diagnose catalina` | Verifies the foreground app bundle and absence of helper agents | Python syntax; macOS 10.15 manual check |
| `diagnostics/diagnose.sh` | `diagnose` routes | Reads system/runtime state; backend probes can change temporary runtime output settings | Help routing; shell syntax; local diagnostics |
| `diagnostics/sdl/gamecontroller.sh` | `launch sdl-gamecontroller` | Selects a compatibility route and launches the requested app | Shell syntax; manual SDL check |

The standalone GameController probe clamps `--seconds` to 1–60 seconds; omitted
or invalid values use the five-second default.
| `diagnostics/dext/repair.py` | repair route | Finds and terminates stale generated DriverKit processes | Python syntax; focused local repair |
| `docs/issues/export.py` | `docs export-external-issues` | Reads GitHub through `gh` and replaces archived issue evidence | Path validation; explicit manual refresh |
| `platform/environment.sh` | Build, diagnostics, notarization, and packaging implementations | Loads one root environment file | Environment and packaging checks; shell syntax |
| `quality/env-audit.py` | `env audit` | Reads environment-file keys without printing values | Environment contract validation |
| `quality/validate-schemas.py` | `check schemas` | Validates the three canonical schemas, every generated controller record, every override, and a newly emitted support report | Draft 2020-12 meta-schema and live producer conformance |

Schema, profile, and full catalog-regeneration commands use the pinned Python
dependencies from `.build/schema-validator` when that environment exists. See
`Resources/Schemas/README.md` for the one-time setup command.
| `quality/test-parsers-macos14.sh` | `test parsers-macos14` | Creates isolated harness and cache directories under `/tmp` | Parser harness gate |
| `quality/validate-scripts.py` | `check scripts` | Reads repository paths and validates Bash and Python syntax | Script-layout validation |
| `quality/validate-swift-structure.py` | `check swift-structure` | Reads Swift paths, sizes, names, and directives | Structural validation |
| `release/bump_version.py` | `release bump-version` | Updates version references after verifying a changelog heading | Python syntax and diff review |
| `release/bundle_version.py` | Release packaging implementations | Derives valid shared app/DEXT bundle versions from Git history and tester sequence state | Python syntax; bundle-version contract |
| `release/dmg-background.py` | Release package implementation | Writes a deterministic PNG to the requested path | Packaging contract |
| `release/install_local.py` | `release install-local` | Packages a release and replaces the local app in `/Applications` | Dispatcher argument checks; Swift packaging contract |
| `release/notarize.sh` | `release notarize` | Uses Apple notarization services, writes submission state, and staples the app | Help and shell checks; release-only CI |
| `release/package.py` | `release package` | Builds signed artifacts, mounts temporary DMGs, notarizes, and writes release output | Swift packaging contracts; release-only CI |
| `release/package_tester.py` | `package tester` | Builds a Developer ID-signed app and embedded DEXT into a private, unnotarized DMG | Swift packaging contracts; Python syntax |
| `release/package_common.py` | Release packaging implementations | Shared deterministic DMG, mount, plist, and cleanup helpers | Python syntax; packaging contract |
| `signing/configure.py` | Signing implementation | Reads profiles and Keychain identities; writes root environment files | Environment contracts; focused local setup |
| `signing/export-github-secrets.sh` | `signing export-github-secrets` | Reads signing material, writes private build output, optionally updates GitHub secrets | Shell syntax; explicit operator action |
| `signing/signing.sh` | `signing` routes | Audits or installs profiles, imports identities, creates CI Keychain state, or configures environment files | Help and shell checks; release CI and local setup |

## Task map

| Goal | Command | Notes |
| --- | --- | --- |
| Install profiles | `./scripts/ojd signing install-profiles` | Copies from `~/Documents/Profiles/` |
| Check installed profiles | `./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile` | Safe output; no identifiers |
| Generate `.env.dev` and optional `.env.release` | `./scripts/ojd signing configure` | Release output is written only when publisher assets are installed |
| Diagnose signing mismatches | `./scripts/ojd signing doctor` | Use before tweaking Xcode settings |
| Build signed dev app | `./scripts/ojd build dev` | Output to `.build/` |
| Generate DriverKit project | `./scripts/ojd driverkit generate` | Writes a fresh ephemeral SwifterKit project under `.build/driverkit/generated/` |
| Check DriverKit generation | `./scripts/ojd check driverkit` | Double-generates, checks metadata/boundaries, and performs an unsigned native build |
| Install signed dev build | `./scripts/ojd build install dev` | Application and generated USB DriverKit extension; the app embeds its service registration |
| Fast install (app only) | `./scripts/ojd build install-fast dev` | Skips a generated system-extension upgrade |
| Package private tester build | `./scripts/ojd package tester` | Writes a Developer ID-signed, unnotarized DMG to `.build/tester-artifacts/`; does not install or publish |
| Bump release version | `./scripts/ojd release bump-version <version>` | Verifies the changelog heading and updates version references |
| Package release DMG | `./scripts/ojd release package [version]` | Builds, notarizes, and staples; version defaults to the package version |
| Package and install locally | `./scripts/ojd release install-local [version]` | Replaces the app in `/Applications` after packaging |

## Distribution paths

Use these paths in order:

1. **Local developer tester build (private sharing).** Configure the local
   Developer ID app and DEXT signing assets, then run:

   ```bash
   ./scripts/ojd package tester
   ```

   This writes a clearly named DMG under `.build/tester-artifacts/` containing
   the signed app and embedded `XboxUSBDevice.dext`, plus a build-info file with
   the full source commit, clean/dirty state, and unique bundle build version
   (numeric release base, or that base with a `d1`…`d255` tester suffix). It
   does not install, publish, or notarize anything. The app and
   DEXT use the local Developer ID
   identities/profiles; the artifact is intentionally **not notarized**, so a
   recipient may need an explicit Gatekeeper override. Apple Development
   artifacts are not supported for arbitrary community tester distribution.
   The recipient only needs the DMG, not a source checkout.

2. **GitHub Actions release (published).** Push a SemVer tag such as
   `0.5.0-beta.3`, or manually dispatch the release workflow with an existing
   SemVer tag. The workflow checks out that exact tag, uses Developer ID signing,
   notarizes and staples the app, then publishes the release DMG to GitHub.
   This path requires the configured GitHub signing and notarization secrets.

## Initial setup (per machine or team)

Start with [Signing assets](../docs/development/signing.md). It lists who can
obtain each Apple asset, the exact App IDs and capabilities, the portal profile
types, and every generated environment value. End users and parser or record
contributors do not need signing assets.

### 1. Provisioning profiles

The scripts look for provisioning profiles at:

- `~/Library/MobileDevice/Provisioning Profiles/`

Install (copies from `~/Documents/Profiles/` or `~/Documents/profiles/`):

```bash
./scripts/ojd signing install-profiles
```

Required development filenames:

- `OpenJoystickDriver.provisionprofile` (GUI, Apple Development)
- `OpenJoystickDriver_XboxUSBDevice.provisionprofile` (DriverKit dext, Apple Development)

Optional publisher-only release filenames:

- `OpenJoystickDriver_DevID.provisionprofile` (GUI, Developer ID)
- `OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile` (DriverKit dext, Developer ID)

`signing install-profiles` succeeds with the two development profiles and
reports that it skipped the optional release profile when it is absent.
The `package tester` path requires these publisher-only Developer ID profiles
and a matching Developer ID Application identity; it never uses the Apple
Development profiles.

Sanity-check what you installed (safe output; no identifiers printed):

```bash
./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
```

### 2. Keychain identities

Development requires:

- `Apple Development: …`

Publisher releases also require:

- `Developer ID Application: …`

```bash
security find-identity -v -p codesigning
```

The Team ID in your provisioning profiles must match the Team ID encoded in your certificate **Subject OU**.
You must not trust the `(...)` suffix in the Keychain display name as the Team ID.

If `security find-identity` shows **0 valid identities**, you are usually missing Apple intermediate CA
certificates (WWDR / Developer ID). Apple publishes them here:

- <https://www.apple.com/certificateauthority/>

### 3. Generate root `.env.dev` and optional `.env.release`

These are the only local environment files loaded. See `../docs/development/environment.md`; run `./scripts/ojd env audit` to validate names without printing values.

This repo reads your Keychain and installed profiles. It always writes
`.env.dev` after validating the two development assets. It writes `.env.release`
only when the optional publisher Developer ID profile and matching identity are
available:

```bash
./scripts/ojd signing configure
```

Re-run this after rotating certificates, regenerating profiles, or switching teams.

## Common tasks

### Application login item

On macOS 13 and newer, `SMAppService.mainApp` registers the main app as a login item.
The app contains no LaunchAgent or helper executable. On macOS 10.15 through 12,
run the app directly; automatic login registration is unavailable.

Commands (run the app-bundled binary):

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login enable
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login disable
```

Launch the installed app directly when the runtime is not running:

```bash
open /Applications/OpenJoystickDriver.app
```

### Dev build (signed) + app bundle

```bash
./scripts/ojd build dev
```

## Generated USB DriverKit extension

SwifterKit is the sole generator and native-project owner for the USB DriverKit
extension. `DriverKitGenerator` consumes the repository's authored USB
configuration and writes a fresh native project at
`.build/driverkit/generated/`; Xcode derived data is kept under
`.build/driverkit/derived-data/`. Both directories are disposable build output.
Do not add or edit a manual native build path or post-generation patch.

Generate for local inspection only:

```bash
./scripts/ojd driverkit generate
```

Prove the supported generated path before changing generation, signing, or
USB configuration:

```bash
./scripts/ojd check driverkit
```

Validation rejects a local SwifterKit override, generates twice and compares the
trees, verifies the stable bundle identity and required DriverKit entitlements,
checks that `OpenJoystickDriverKit` does not import SwifterKit, and performs an
unsigned native build. It does not sign, activate, or hardware-test an extension.
Generated-source validation proves that the output-only allowlist rejects feature
reports synchronously before payload access or event delivery. A signed
HID-boundary check remains required to prove that behavior on a target macOS
runtime.

### Build the DriverKit system extension (.dext)

```bash
./scripts/ojd build dext
```

This route regenerates the project before building it, then embeds the resulting
`com.openjoystickdriver.XboxUSBDevice.dext` in the app. The host application
must be signed with the exact
`com.apple.developer.driverkit.userclient-access` allowlist for that bundle ID;
allow-any user-client access is rejected. `signing configure` and the build
pipeline require the exact single-DEXT grant. If this build fails due to
certificate or profile matching, see the Troubleshooting section below.

## Notarization

Store notarization credentials in the macOS Keychain:

```bash
./scripts/ojd release notarize store-credentials OJDNotary
```

Put these into `.env.release`:

- `NOTARIZE_KEYCHAIN_PROFILE` (the notarytool Keychain profile name)

Then:

```bash
./scripts/ojd build install release
./scripts/ojd release notarize submit
./scripts/ojd release notarize status
```

### Release package

For a release build that does not install anything on the build machine:

```bash
./scripts/ojd release package 0.5.0-beta.3
```

This command uses release signing, regenerates and embeds the USB DriverKit extension into the app
bundle, submits the app for notarization, staples the accepted ticket, verifies
the result, and writes a drag-and-drop DMG containing `OpenJoystickDriver.app`
and an `Applications` symlink:

```text
.build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg
```

The package command does not register a login item and does not submit a
system-extension activation request on the build machine. Testers still need to
install and approve the app/system extension locally. Notarization and package
creation do not prove activation or HID delivery on a tester's Mac.

## GitHub Actions release

`.github/workflows/release.yml` runs on SemVer tags such as `0.1.0` or
`0.5.0-beta.3` and by manual dispatch.
It validates profiles, imports signing material, builds a release app, notarizes
it, uploads the release DMG as a workflow artifact, and
publishes the GitHub Release.

### Required repository secrets

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `CERTIFICATE_SECRET`
- `KEYCHAIN_SECRET`
- `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_PASSWORD`

The certificate payload secrets are base64-encoded certificate export files.
The profile secrets are base64-encoded `.provisionprofile` files.

### Generate GitHub secrets locally

To collect all release secrets in one local step:

```bash
./scripts/ojd signing export-github-secrets \
  --developer-id-identity /path/to/DeveloperIDApplication.p12 \
  --repo xsyetopz/OpenJoystickDriver
```

The script reads the two installed release provisioning
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
./scripts/ojd signing export-github-secrets \
  --developer-id-identity /path/to/DeveloperIDApplication.p12 \
  --repo xsyetopz/OpenJoystickDriver \
  --apply
```

Keep `.build/github-actions-secrets/` private. It contains raw secret values.

Export the Developer ID Application identities selected by both release profiles
into one password-protected `.p12` and pass it with
`--developer-id-identity`. The profiles may use different certificates from the
same team. The release workflow does not accept an Apple Development identity.

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
  -in "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_XboxUSBDevice.provisionprofile" 2>/dev/null \
  | plutil -extract TeamIdentifier.0 raw -o - -
```

If those Team IDs differ:

1. Create an **Apple Development** certificate for the **same team** as the provisioning profiles.
2. Import the downloaded `.cer` into Keychain Access (it must include a private key).
3. Regenerate the Apple Development provisioning profiles (application and generated USB DriverKit extension) selecting that certificate.
4. Reinstall profiles: `./scripts/ojd signing install-profiles`
5. Re-generate env files: `./scripts/ojd signing configure`

Entitlement note for `com.apple.developer.hid.virtual.device`:

- It must be present on the application identifier that creates the virtual device.
- In this repo it belongs to the main application executable.
- The DriverKit `.dext` must not contain this app-only entitlement.

The same host profile must contain exactly this DriverKit user-client entitlement:

```text
com.apple.developer.driverkit.userclient-access = [com.openjoystickdriver.XboxUSBDevice]
```

Do not replace it with `com.apple.developer.driverkit.allow-any-userclient-access`.

Older profiles may contain the removed daemon bundle ID or allow-any access.
Follow [Replace invalid profile entitlements](../docs/development/signing.md#replace-invalid-profile-entitlements)
to replace the Apple capability grant and regenerate all three profiles.

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
