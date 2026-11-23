---
name: writing-ojd-controller-patches
description: Writes an OpenJoystickDriver ControllerPatch that changes a bundled controller record, such as a deadzone, the handler, or a mode key. Use when ojd knows a model but one detail is wrong.
---

# Writing OJD Controller Patches

Goal: change a few keys of a controller record that OJD already has, with a validated and installed `ControllerPatch`.

## Inputs

- `VVVV:PPPP`: the model, in hex.
- The change: which key and value, grounded in `ojd controller watch`, a capture, or the maker's documentation.

## Format

- Every document is an XML property list. Write JSON first, then convert: `plutil -convert xml1 -o vvvv-pppp.patch.plist patch.json`.
- Read a property list as JSON with `plutil -convert json -o - FILE.plist`.
- The file name is `vvvv-pppp.patch.plist` with lowercase hex.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha3",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 746 },
  "patch": { "tuning": { "stickDeadzone": 0.08 } }
}
```

## Merge Rules

- `selector`: decimal `vendorID` and `productID`, or `model` (such as `045E-028E`), or `all` set to `true`.
- `patch`: dictionaries merge key by key. A scalar overrides. An array replaces the whole array.
- `modes`: entries merge by `id`. An existing `id` merges into that mode. A new `id` adds a mode.
- `remove`: dotted key paths deleted before the merge, such as `tuning.stickDeadzone` or `modes.<id>`. Use it to delete a key; property lists have no `null`. Remove a whole section instead of its last key.
- A patch cannot change `vendorID` or `productID`.

## Procedure

1. Run `ojd record show VVVV:PPPP`. If it exits 1, stop and use `writing-ojd-controller-records`.
2. Optional: run `ojd record draft VVVV:PPPP > draft.plist` while the user presses every control for 10 seconds.
3. Write the patch with only the keys that change.
4. Run `ojd record validate FILE`. Exit 1 means invalid or no change. Fix the key path it names and repeat.
5. Run `ojd record install FILE --dry-run`. Show the user the target path.
6. Run `ojd record install FILE`. The running service applies it. A controller connected earlier needs a reconnect.
7. Run `ojd record show VVVV:PPPP`. Confirm the changed field shows layer `User`.

## Key Lookup

| Goal | Key |
| --- | --- |
| stick deadzone | `tuning.stickDeadzone` |
| OJD handles the pad | `server` = `OJD`, or `ojd controller claim CONTROLLER` |
| macOS handles the pad | `server` = `System`, or `ojd controller release CONTROLLER` |
| wrong button bit | `input.layouts`; see `writing-ojd-controller-records` |
| rumble | `modes[].session.rumble`; see `adding-ojd-rumble` |

Layer order, weakest first: bundled record, bundled patch, mod package patch, user patch. A unit patch for one controller applies last.

## Outputs

- `vvvv-pppp.patch.plist`, validated and installed.
- The `ojd record show` lines that prove the change.
- The undo command: `ojd record remove VVVV:PPPP`.

## Stop Conditions

- Stop and ask before passing `--force` to replace an installed file.
- Stop and ask when a value has no source.
