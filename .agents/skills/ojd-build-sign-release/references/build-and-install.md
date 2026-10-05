# Build and Install

## Contents

- [Build routes](#build-routes)
- [Stale DEXT](#stale-dext)
- [Module cache](#module-cache)

## Build Routes

**Definition.** These routes come from `./Scripts/ojd --help`:

| Command | Effect |
| --- | --- |
| `./Scripts/ojd build dev` | Builds and signs the app bundle into `.build/`, without the DEXT |
| `./Scripts/ojd build release` | Same, with release signing |
| `./Scripts/ojd build dext` | Builds the DriverKit `.dext` and embeds it into the `.build/` app |
| `./Scripts/ojd build install dev\|release` | Full rebuild, then installs to `/Applications` |
| `./Scripts/ojd build install-fast dev` | Rebuilds and installs the app only, and keeps the installed system extension |

`just install-dev`, `just install-release`, and `just install-fast-dev` wrap the install routes. A signed operation searches the known profile locations, installs the profiles it finds, configures the matching Keychain identities, then resumes.

**Use when.** Testing a change in the real app. Use `install-fast` when nothing under `Sources/DriverKitGenerator` or the DEXT changed.

**Do not use when.** The change is covered by `swift test` alone. Do not install when no runtime check needs it.

**Verify.** The version provenance in `ojd diagnose` shows the built commit, and `./Scripts/ojd diagnose dext` reports activation.

## Stale DEXT

**Definition.** `./Scripts/ojd repair stale-dext` kills stale DriverKit process copies that are left behind after an upgrade.

**Use when.** `diagnose dext` shows an older DEXT process still bound after `build install dev`.

**Do not use when.** The extension was never approved. Approve it in System Settings first.

**Verify.** Run `./Scripts/ojd diagnose dext` again. It shows one process for the installed version.

## Module Cache

**Definition.** `./Scripts/ojd repair swiftpm-module-cache` cleans SwiftPM build products after a toolchain or target change.

**Use when.** A build fails with a SwiftPM module-cache mismatch, for example after switching Xcode or moving files between targets.

**Do not use when.** The failure is any other compile error. Cleaning hides nothing, and costs a full rebuild.

**Verify.** The failed command succeeds on rerun.
