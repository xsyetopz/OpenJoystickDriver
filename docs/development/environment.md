# Environment Files

Repository scripts load exactly one optional local file from the project root:

- `.env.dev` for development commands (the default);
- `.env.release` for publisher release, notarization, and packaging commands.

`OJD_ENV` selects `dev` or `release`; other values fail immediately. Scripts do not load generic `.env` or `Scripts/.env*` files. Signed build and package routes create or repair the appropriate root file from discovered Apple assets.

Examples show annotated output; never source identities, profiles, Team IDs, or credentials from them. Read [Signing assets](signing.md) before creating either local file. Development configuration requires the two development profiles and an Apple Development identity; publisher-only Developer ID assets are optional and do not block `.env.dev` generation.

Unsigned `swift build` and `./Scripts/ojd check driverkit` do not load `.env.dev`. Signed local development installs create or repair `.env.dev` before building. Notarization keys belong only in `.env.release`; they are not inputs to unsigned or Apple Development builds.

The signing configurator updates recognized signing keys in the selected root file, preserving unrelated recognized publisher keys. Never commit actual `.env.dev` or `.env.release` files.

## GitHub Actions Secrets

`.github/workflows/release.yml` remains the source of truth for GitHub Secret names. Only inputs used by the single-app release remain:

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `CERTIFICATE_SECRET`
- `KEYCHAIN_SECRET`
- `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_PASSWORD`

GitHub injects workflow secrets directly; CI neither creates nor requires a local `.env` file. GitHub does not allow reading those values back. The local analogues are:

- certificate and profile secrets → Keychain identities plus the Developer ID profiles consumed by `signing configure` (or `signing ci-release-setup` on the runner);
- `NOTARIZE_APPLE_ID` / `NOTARIZE_PASSWORD` → the same keys in `.env.release`, or `NOTARIZE_KEYCHAIN_PROFILE` after storing credentials in Keychain.

Do not copy the CI-only `*_BASE64` / `CERTIFICATE_SECRET` / `KEYCHAIN_SECRET` keys into `.env.dev` or `.env.release`.

The GUI provisioning profile must authorize the host app's exact `com.apple.developer.driverkit.userclient-access` allowlist, exactly `com.openjoystickdriver.XboxUSBDevice`. The DriverKit profile (`DEXT_PROVISIONING_PROFILE`, whose `Name` the build passes to Xcode as the profile specifier) authorizes the single system extension. The build rejects an allow-any user-client entitlement in either artifact. A development GUI profile without a grant for `com.openjoystickdriver.XboxUSBDevice` builds the app without the DEXT; see [Signing](signing.md).

## Environment variables

Each row names who sets a variable, who reads it, whether it stays and why. A row can group variables that share the setter, the reader and the reason. The repository reads no environment variable that is not in this table.

`.env.dev` and `.env.release` hold only the signing keys of the kept rows (`CODESIGN_IDENTITY`, `DEVELOPMENT_TEAM`, `GUI_PROVISIONING_PROFILE`, `DEXT_PROVISIONING_PROFILE`, `OJD_USE_LOCAL_SWIFTERKIT`), plus the `NOTARIZE_*` keys in `.env.release`. `Scripts/Platform/env_file.py` reads both files and stops every script with exit status 2 on any other key or on a line that is not `KEY=value`, naming the file, the line and the allowed keys.

| Name | Set by | Read by | Status | Reason |
| --- | --- | --- | --- | --- |
| `OJD_ENV` | contributor, `release` routes, release workflow | `environment.sh`, `dispatcher.py`, `package.py`, `package_tester.py`, `notarize.sh`, `driverkit.sh`, `bundles.sh` | kept | Selects `.env.dev` or `.env.release`. |
| `CODESIGN_IDENTITY` | `.env.*` (written by `signing configure`) | `environment.sh`, `build.sh`, `driverkit.sh`, `package.py`, `package_tester.py`, `capabilities.py` | kept | The one identity that signs the app, its bundles and the DEXT; unset signs ad hoc. |
| `DEVELOPMENT_TEAM` | `.env.*` | `environment.sh`, `bundles.sh`, `driverkit.sh`, `notarize.sh` | kept | Team ID. |
| `GUI_PROVISIONING_PROFILE` | `.env.*` | `environment.sh`, `capabilities.py` | kept | Path of the app provisioning profile. |
| `DEXT_PROVISIONING_PROFILE` | `.env.*` | `driverkit.sh`, `capabilities.py` | kept | Path of the DEXT provisioning profile; the build passes its `Name` to Xcode as the profile specifier. |
| `NOTARIZE_APPLE_ID` | `.env.release`, GitHub secret | `notarize.sh` | kept | Notarization account. |
| `NOTARIZE_PASSWORD` | `.env.release`, GitHub secret | `notarize.sh` | kept | Notarization app-specific password. |
| `NOTARIZE_KEYCHAIN_PROFILE` | `.env.release` (written by `notarize store-credentials`) | `notarize.sh` | kept | Keychain profile that replaces the Apple ID and password. |
| `DEVELOPER_ID_APPLICATION_CERT_BASE64` | GitHub secret | `signing.sh ci-release-setup` | kept | Release certificate on the runner. |
| `CERTIFICATE_SECRET` | GitHub secret | `signing.sh ci-release-setup`, `export-github-secrets.sh` | kept | Password of the release certificate. |
| `KEYCHAIN_SECRET` | GitHub secret | `signing.sh ci-release-setup`, `export-github-secrets.sh` | kept | Password of the runner keychain. |
| `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64` | GitHub secret | `signing.sh ci-release-setup` | kept | App Developer ID profile on the runner. |
| `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE_BASE64` | GitHub secret | `signing.sh ci-release-setup` | kept | DEXT Developer ID profile on the runner. |
| `OJD_BUNDLE_SHORT_VERSION` | repository scripts: `package.py`, `package_tester.py` | `bundles.sh`, `driverkit.sh` | kept | Version of the bundle being built, passed from the Python release route to the bash build. |
| `OJD_BUNDLE_VERSION` | repository scripts: `package.py`, `package_tester.py`, `install.sh` | `bundles.sh`, `driverkit.sh` | kept | Build number of the app and the DEXT; `install.sh` passes a development-stage number so a rebuilt tree replaces the installed one. |
| `OJD_SOURCE_COMMIT`, `OJD_SOURCE_STATE` | repository scripts: `package.py`, `package_tester.py` | `bundles.sh` | kept | Source facts stamped into the bundle, passed from the Python release route to the bash build. |
| `OJD_USE_LOCAL_SWIFTERKIT` | contributor, CI (`0`) | `Package.swift`, `driverkit.sh` | kept | Builds the sibling `../SwifterKit` checkout; CI and release builds reject `1`. |
| `OJD_RUN_REPOSITORY_CLI` | contributor, `validate_schemas.py` | `InstalledCLIForwarder.swift` | kept | Runs a repository build of `ojd`; named in error E2020. |
| `OJD_HIDDEN` | contributor, screenshot scripts (`open -g --env OJD_HIDDEN=1 -a OpenJoystickDriver`) | `AppForeground.swift` | kept | `1`, `true` or `yes` keeps the app inactive and orders each window it shows behind other apps' windows, so `screencapture -l` can capture it without taking focus. |
| `OJD_COLOR`, `OJD_NO_INPUT`, `OJD_TIMEOUT` | user | `GlobalOptions.swift` | kept | User options documented in the wiki page Command-Line. |
| `OJD_TOKEN` | user, WebRTC bridge launcher | `reference_client.py`, `WebRTCBridge` | kept | Endpoint token, documented in `docs/sdk/endpoint.md` and the wiki page WebRTC-Bridge. |
| `OJD_SNAPSHOT_WRITE`, `OJD_SNAPSHOT_ACTUAL_DIR` | `equivalence_snapshots.py` | `EquivalenceSnapshotStore.swift` | kept | `swift test` takes no arguments, so `./Scripts/ojd snapshots check` and `snapshots write` tell the test process through the environment. |
| `VISUAL`, `EDITOR` | user | `ProfileFileCommands.swift` | kept | Editor that `ojd profile edit` opens, documented in the wiki page Command-Reference. |
| `SDL_GAMECONTROLLERCONFIG`, `SDL_JOYSTICK_*` | `SDLLaunchEnvironment.swift`, user | `SDLLaunchEnvironment.swift`, `Tools/SDLGamepadProbe`, `backend.sh`, SDL games | kept | SDL settings that `ojd virtual launch` passes to a game; the launcher appends to an existing `SDL_GAMECONTROLLERCONFIG`, and the probe prints them. |
| `DEVELOPER_DIR`, `SDKROOT` | contributor, CI, `environment.sh` | Xcode tools, `swift`, `swiftlint`, `justfile` | kept | Select the Xcode SDK and tools; the compiler is the `swift` on `PATH`. |
| `TOOLCHAINS` | contributor | `bundles.sh` (unset for `xcodebuild`) | kept | `xcodebuild` cannot resolve the package under a swift.org toolchain. |
| `CI` | GitHub Actions | `driverkit.sh`, `signing.sh`, `notarize.sh`, `capabilities.py` | kept | Turns off prompts and rejects local SwifterKit. |
| `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_TOKEN` | GitHub Actions | `wiki/build.py`, `package.py`, `wiki.yml` | kept | Repository and ref facts only the runner knows. |
| `RUNNER_TEMP`, `GITHUB_OUTPUT`, `GITHUB_PATH` | GitHub Actions | `signing.sh ci-release-setup`, workflow and action steps | kept | Runner scratch directory and step outputs. |
| `RELEASE_TAG`, `RELEASE_TAG_INPUT`, `GH_TOKEN` | release workflow | workflow shell steps | kept | Tag and token of the release job. |
| `NO_COLOR`, `TERM`, `PAGER`, `HOME`, `PATH`, `HUSKY`, `TMPDIR` | shell, Git, user | `ojd`, scripts, hooks | kept | Standard variables with their standard meaning. |
| `SWIFT_BIN`, `SWIFT_BUILD_BIN`, `SWIFT_PACKAGE_BIN` | `environment.sh` | `execution.py`, `driverkit.sh` | removed | Every Swift call runs `swift` from `PATH`, so no route needs a compiler path. |
| `OJD_NONINTERACTIVE` | nobody | `capabilities.py`, `signing.sh`, `notarize.sh` | removed | `CI` and the absence of a terminal turn prompts off. |
| `OJD_APPLICATIONS_DIR` | `test_capabilities.py` | `capabilities.py` | removed | A test seam; `Resolver` takes an `applications_dir` parameter. |
| `OJD_NOTARIZE_PROFILE` | nobody | `capabilities.py` | removed | The keychain profile name is the constant `NOTARIZE_KEYCHAIN_PROFILE_NAME`. |
| `NOTARIZE_TIMEOUT_MINUTES`, `NOTARIZE_POLL_INTERVAL`, `NOTARIZE_MAX_RETRIES` | nobody | `notarize.sh` | removed | Fixed values of the script (180 minutes, 30 seconds, 5 retries). |
| `NOTARIZE_KEYCHAIN` | nobody | `notarize.sh` | removed | No route sets a custom keychain. |
| `DEV_ENV`, `REL_ENV`, `SCRIPT_DIR`, `PROJECT_DIR` | `signing.sh` | `configure.py` | removed | `configure.py` takes `--project-dir` and derives the root `.env.dev` and `.env.release` paths from it. |
| `GUI_CODESIGN_IDENTITY`, `DEXT_BUILD_IDENTITY` | `.env.*` | `environment.sh`, `driverkit.sh`, `package_tester.py` | removed | Both profiles embed one identity, so `CODESIGN_IDENTITY` signs the app and the DEXT. |
| `DEXT_BUILD_PROFILE` | `.env.*` | `driverkit.sh`, `package_tester.py` | removed | The build reads the profile specifier from the `Name` inside `DEXT_PROVISIONING_PROFILE`. |
| `GUI_DEV_PROFILE`, `GUI_DEVID_PROFILE`, `DEXT_PROFILE`, `DEXT_DEVID_PROFILE` | nobody | `signing.sh`, `configure.py` | removed | `signing install-profiles` copies the profiles under fixed names, which `signing configure` reads. |
| `APPLE_DEV_IDENTITY`, `DEVID_APP_IDENTITY` | contributor | `signing.sh` | removed | `signing configure --development-identity <sha1>` and `--release-identity <sha1>` pick an identity. |
| `OJD_SIGNING_MODE` | `signing.sh ci-release-setup`, `capabilities.py` | `signing.sh`, `configure.py` | removed | `signing configure --mode` and `signing install-profiles --mode` take `development`, `release` or `all`. |
| `OJD_NOTARIZE_APP`, `OJD_NOTARIZE_ZIP` | `package.py`, `package_tester.py`, `install.sh` | `notarize.sh` | removed | `notarize.sh submit <app> <zip>` takes them as arguments. |
| `DEXT_BUNDLE_VERSION` | `install.sh` | `driverkit.sh` | removed | `install.sh` passes the build number in `OJD_BUNDLE_VERSION`, which `driverkit.sh` reads. |
| `OJD_ENABLE_CONTRIBUTOR_USB_PASSIVE` | contributor | `PassiveUSBDescriptorProbe.swift` | removed | The probe reads IORegistry facts of one allowlisted device and claims nothing, the same read the app makes on every USB attach; `--usb-passive` and the tuple allowlist are its opt-in. |
| `DEVELOPER_ID_APPLICATION_IDENTITY_EXPORT`, `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE`, `OPENJOYSTICKDRIVER_DEXT_DEVID_PROFILE` | nobody | `export-github-secrets.sh` | removed | Overrides of fixed paths and of the `--identity` option. |
| `OJD_REGENERATE_REPORT_FIXTURE` | contributor | `SupportReportBindingTests.swift` | removed | The support report fixture is the equivalence snapshot `Tests/EquivalenceSnapshots/support-report-binding.json`, which `./Scripts/ojd snapshots write` rewrites and `snapshots check` diffs. |
| `OJD_ENV_FILE` | `environment.sh` | `notarize.sh` | removed | `notarize.sh` sources `environment.sh`, so it is a shell variable, not an exported one. |

Shell variables of one script (`IDENTITY`, `OJD_HOST_USERCLIENT`, `OJD_APP_INFO_PLIST`, `OJD_DEFAULT_BUNDLE_SHORT_VERSION`, `OJD_APP_CLI`, `OJD_ENV_FILE`) and values that tests pass as a fixture parameter (`OJD_ARGUMENT`, `OJD_LAUNCH_TEST`) are not environment inputs.

This command counts the names in the table by status:

```sh
awk -F'|' '$5 ~ /^ (kept|removed) $/ { status = $5; gsub(/ /, "", status)
  count[status] += gsub(/`[A-Z][A-Z0-9_]*\*?`/, "&", $2) }
  END { print "kept", count["kept"]; print "removed", count["removed"] }' docs/development/environment.md
```

It prints `kept 50` and `removed 33`; `SDL_JOYSTICK_*` counts as one name.

## Swift toolchain

Every Swift command runs the `swift` of the selected Xcode, so one compiler writes `.build`. `Scripts/Platform/environment.sh` puts `$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin` first on `PATH` and stops with exit status 2 unless `swift --version` reports the release `.swift-version` names or a newer one (a version without a patch number counts as `.0`). The swift.org toolchains from 6.0.1 on build their runtime libraries for macOS 13, so linking the macOS 12 floor against them warns; Xcode's toolchain links against the SDK. `./Scripts/ojd check swift` builds the package and its tests and fails on any `warning:` line of the build output, then runs the tests without building again; `check tools` applies the same rule to the SDL probe and the WebRTC bridge. The CI Toolchain step prints the `swift` that `environment.sh` selects.
