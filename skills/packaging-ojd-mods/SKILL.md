---
name: packaging-ojd-mods
description: Packages OpenJoystickDriver records, patches, profiles, virtual devices, and protocol descriptions as a mod folder with a mod.plist manifest. Use when sharing ojd files with other users.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha3
---

# Packaging OJD Mods

A mod package is a folder of settings files with a `mod.plist` manifest. It is a read-only layer between the bundled catalog and the user's own files. It never holds or runs a program.

## Steps

1. Validate each document first: `ojd record validate FILE` for records and patches, `ojd protocol validate FILE` for protocol descriptions.
2. Lay out the folder: `Controllers/`, `Profiles/`, `VirtualDevices/`, `Protocols/`, with file names as in [references/manifest.md](references/manifest.md).
3. Write `mod.plist`. List every file in its manifest list, and nothing else. Put `ControllerPatch` files under `patches`, `Controller` files under `controllers`.
4. Set `requires.minimum` to the first OJD version the files need, and `requires.below` when a later version breaks them. Read the running version from `ojd --version`.
5. Check: `ojd mod validate FOLDER`. Exit 1 prints an `E4xxx` or `E5001` code; `ojd explain CODE` explains it.
6. Preview the install: `ojd mod install FOLDER --dry-run`.
7. Install: `ojd mod install FOLDER`. The running service applies it without a restart.
8. Confirm: `ojd mod list` shows the package, or the reason and code it is unused. `ojd record list` names each ignored package record.

Remove with `ojd mod remove NAME`. It asks first on a terminal.

## Rules

- `name` uses lowercase letters, digits, and hyphens; `version` is SemVer with no `v`.
- A package `Controller` is only for a model with no bundled record. Change a bundled model with a `ControllerPatch`.
- Any file outside the layout is refused. Hidden files and `.js` files are skipped.
- A clash with the user's files or another package (`E4004`) is a real conflict. Rename or drop the file; `--force` does not override it.
- `--force` replaces an installed package of the same name only. Ask the user before passing it.
- Shared packages use real VID:PIDs, not the `1209` pid.codes test IDs.
- A development build refuses every package in `mod validate` and `mod install`; test on a release build.
