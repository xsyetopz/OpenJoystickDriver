---
name: writing-ojd-controller-patches
description: Writes an OpenJoystickDriver ControllerPatch that changes a bundled controller record, such as a deadzone, the handler, or a mode key. Use when ojd knows a model but one detail is wrong.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha3
---

# Writing OJD Controller Patches

A `ControllerPatch` changes a few keys of a record OJD already has. For a model with no record, write a `Controller` record instead (`writing-ojd-controller-records`).

## File Shape

Every document is an XML property list. Draft it as JSON, then convert: `plutil -convert xml1 -o FILE.plist FILE.json`. `plutil -convert json -o - FILE.plist` reads one back.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha3",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 746 },
  "patch": { "tuning": { "stickDeadzone": 0.08 } }
}
```

- `selector` names the model by decimal `vendorID` and `productID`, by `model` (such as `045E-028E`), or with `all` set to `true`.
- `patch` merges into the record: dictionaries key by key, a value overrides, an array replaces the whole array.
- `modes` merges by `id`: an existing `id` merges into that mode, a new `id` adds a mode.
- `remove` lists dotted key paths deleted before the merge, such as `tuning.stickDeadzone` or `modes.<id>`. A property list has no `null`, so `remove` is the only way to delete a key. Remove a whole section instead of its last key, because an empty section is invalid.
- A patch sets any property except `vendorID` and `productID`.
- Name the file `vvvv-pppp.patch.plist` in lowercase hex.

## Steps

1. Confirm a record exists: `ojd record show VVVV:PPPP`. Exit code 1 means none; switch to a record.
2. Draft from the connected pad: `ojd record draft VVVV:PPPP > vvvv-pppp.patch.plist`, pressing every control for 10 seconds. The draft is a patch when a bundled record exists.
3. Keep only the keys that change. Delete drafted keys that match the bundled record.
4. Validate: `ojd record validate vvvv-pppp.patch.plist`. It exits 1 for an invalid patch or one that changes nothing; fix the key path it names.
5. Preview, then install: `ojd record install vvvv-pppp.patch.plist --dry-run`, then without `--dry-run`. The running service applies it.
6. Verify: `ojd record show VVVV:PPPP` lists each field and its layer. A pad connected earlier picks up the change on reconnect.

Undo with `ojd record remove VVVV:PPPP`.

## Common Patches

| Goal | Patch |
| --- | --- |
| stick deadzone | `tuning.stickDeadzone` |
| OJD handles the pad instead of macOS | `server` `OJD`, or run `ojd controller claim CONTROLLER` |
| macOS handles the pad | `server` `System`, or run `ojd controller release CONTROLLER` |
| a wrong button bit | `input.layouts` (see `writing-ojd-controller-records`) |
| rumble on a silent pad | `modes[].session.rumble` (see `adding-ojd-rumble`) |

## Layers

Weakest to strongest: bundled record, bundled patch, mod package patch, the user's patch. Inside a layer: `all`, then `vendorID` and `productID`, then `model`. A unit patch for one controller applies last.

## Rules

- Change a bundled model only by patch; OJD refuses a `Controller` file for it.
- Replacing an installed file asks first on a terminal. Ask the user before passing `--force`.
- Ground each value in `ojd controller watch`, `capture`, or the maker's documentation, never a guess.
