---
name: packaging-ojd-mods
description: Packages OpenJoystickDriver records, patches, profiles, virtual devices, and protocol descriptions as a mod folder with a mod.plist manifest. Use when sharing ojd files with other users.
---

# Packaging OJD Mods

Goal: turn validated OpenJoystickDriver documents into a mod package that `ojd mod validate` accepts.

## Inputs

- The documents to share: `Controller` and `ControllerPatch` files, profiles, `VirtualDevice` files, protocol descriptions.
- A package name (lowercase letters, digits, hyphens), a SemVer version without `v`, and an author.

Read [references/manifest.md](references/manifest.md) for the layout, manifest keys, file names, and refusal codes.

## Procedure

1. Validate each document: `ojd record validate FILE` for records and patches, `ojd protocol validate FILE` for protocol descriptions.
2. Create the folder with the subfolders the files need: `Controllers/`, `Profiles/`, `VirtualDevices/`, `Protocols/`.
3. Write `mod.plist` (JSON first, then `plutil -convert xml1 -o mod.plist mod.json`):
   - List every file exactly once, in the list for its kind.
   - `ControllerPatch` files go under `patches`; `Controller` files go under `controllers`.
   - Add no other keys.
4. Run `ojd --version`. Set `requires.minimum` to the first version the files need. Set `requires.below` only when a later version breaks them.
5. Run `ojd mod validate FOLDER`. On exit 1, run `ojd explain CODE` for the `E4xxx` or `E5001` code, fix it, and repeat.
6. Run `ojd mod install FOLDER --dry-run`.
7. Run `ojd mod install FOLDER`. The running service applies it without a restart.
8. Run `ojd mod list` and `ojd record list`. Report any unused package or ignored record with its reason.

## Outputs

- A package folder that `ojd mod validate` accepts.
- The `ojd mod list` line for the installed package.
- The removal command: `ojd mod remove NAME`.

## Stop Conditions

- A package `Controller` file for a model with a bundled record: stop and convert it to a `ControllerPatch`.
- `E4004` (clash with the user's files or another package): stop and ask the user which file to rename or drop. `--force` does not override it.
- Ask the user before passing `--force`; it only replaces an installed package of the same name.
- A development build refuses every package in `mod validate` and `mod install`. Report this and test on a release build.
- Do not ship the `1209` pid.codes test vendor ID in a shared package.
