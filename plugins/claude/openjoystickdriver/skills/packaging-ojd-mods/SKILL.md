---
name: packaging-ojd-mods
description: Packages OpenJoystickDriver records, patches, profiles, virtual devices, and protocol descriptions as a mod folder with a mod.plist manifest. Use when sharing ojd files with other users.
argument-hint: "[package folder]"
allowed-tools: Bash(ojd mod validate *) Bash(ojd mod install * --dry-run) Bash(ojd mod list) Bash(ojd record validate *) Bash(ojd protocol validate *) Bash(ojd --version) Bash(plutil *)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha3
---

# Packaging OJD Mods

Folder: $ARGUMENTS

A mod is a folder of settings files plus `mod.plist`. It is a read-only layer between the bundled catalog and the user's files, and never runs code.

Layout, manifest keys, file names, and every refusal code: [references/manifest.md](references/manifest.md).

## Workflow

```text
- [ ] validate each document: ojd record validate FILE / ojd protocol validate FILE
- [ ] lay out Controllers/ Profiles/ VirtualDevices/ Protocols/
- [ ] write mod.plist: every file listed once, nothing else
      ControllerPatch → patches, Controller → controllers
- [ ] requires.minimum from `ojd --version`; requires.below when a later version breaks it
- [ ] ojd mod validate FOLDER          E4xxx/E5001 → ojd explain CODE
- [ ] ojd mod install FOLDER --dry-run
- [ ] ojd mod install FOLDER           service applies it live
- [ ] ojd mod list; ojd record list    unused packages and ignored records show a reason
```

## Judgment Calls

- A package `Controller` is only for a model with no bundled record; bundled models get a `ControllerPatch`.
- `E4004` is a real clash with the user's files or another package. Rename or drop the file; `--force` cannot override it.
- `--force` only replaces a same-name installed package. Ask first.
- Development builds refuse every package in `mod validate` and `mod install`; test on a release build.
- Real VID:PIDs only in shared packages, never the `1209` test vendor.
- Hidden and `.js` files are skipped; anything else outside the layout is refused.

Remove: `ojd mod remove NAME` (asks on a terminal).
