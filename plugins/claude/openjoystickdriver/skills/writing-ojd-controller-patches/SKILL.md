---
name: writing-ojd-controller-patches
description: Writes an OpenJoystickDriver ControllerPatch that changes a bundled controller record, such as a deadzone, the handler, or a mode key. Use when ojd knows a model but one detail is wrong.
argument-hint: "[VVVV:PPPP] [change]"
allowed-tools: Bash(ojd record show *) Bash(ojd record validate *) Bash(ojd record install * --dry-run) Bash(plutil *)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Writing OJD Controller Patches

Request: $ARGUMENTS

A `ControllerPatch` changes a few keys of a record OJD has. No record (`ojd record show VVVV:PPPP` exits 1) means a `Controller` record instead: `/openjoystickdriver:writing-ojd-controller-records`.

## Shape

Draft as JSON, convert with `plutil -convert xml1 -o vvvv-pppp.patch.plist FILE.json` (lowercase hex name). Read one with `plutil -convert json -o - FILE.plist`.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha4",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 746 },
  "patch": { "tuning": { "stickDeadzone": 0.08 } }
}
```

Merge semantics, which decide what the patch must contain:

- `patch`: dictionaries merge per key; scalars override; arrays replace whole.
- `modes`: merge by `id`. Same `id` merges into that mode; new `id` adds one.
- `remove`: dotted paths deleted before the merge (`tuning.stickDeadzone`, `modes.<id>`). The only way to delete, since plists have no `null`. Remove a whole section rather than its last key; an empty section is invalid.
- `selector`: decimal `vendorID` + `productID`, or `model` (`045E-028E`), or `all: true`. `vendorID` and `productID` cannot be patched.

## Workflow

```text
- [ ] ojd record show VVVV:PPPP                 record exists; note each field's layer
- [ ] ojd record draft VVVV:PPPP > draft.plist  optional; user presses every control 10 s
- [ ] keep only changed keys
- [ ] ojd record validate FILE                  exit 1 = invalid or no-op; fix the named path
- [ ] ojd record install FILE --dry-run
- [ ] ojd record install FILE                   service applies it; reconnect older pads
- [ ] ojd record show VVVV:PPPP                 the field now shows layer User
```

Undo: `ojd record remove VVVV:PPPP`.

## Targets

| Goal | Key |
| --- | --- |
| deadzone | `tuning.stickDeadzone` |
| OJD handles the pad | `server: OJD` (or `ojd controller claim CONTROLLER`) |
| macOS handles the pad | `server: System` (or `ojd controller release CONTROLLER`) |
| wrong button bit | `input.layouts`, see `/openjoystickdriver:writing-ojd-controller-records` |
| rumble | `modes[].session.rumble`, see `/openjoystickdriver:adding-ojd-rumble` |

Layers, weakest first: bundled record, bundled patch, package patch, user patch; a unit patch applies last.

Every value traces to `watch`, `capture`, or maker docs. Ask before `--force`.
