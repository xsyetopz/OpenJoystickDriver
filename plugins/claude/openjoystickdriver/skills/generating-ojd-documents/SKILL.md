---
name: generating-ojd-documents
description: Writes a JavaScript generator that ojd generate turns into checked OpenJoystickDriver records, patches, profiles, or virtual devices. Use when several controller models differ by a few details.
argument-hint: "[script.js]"
allowed-tools: Bash(ojd generate *) Bash(ojd record validate *)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Generating OJD Documents

Script: $ARGUMENTS

`ojd generate` calls the script's `generate()` and writes each returned document as a checked property list. One model needs no script; write a record or patch.

## Contract

`function generate()` takes no argument and returns a document or a non-empty list. Each document is a plain object of its plist keys with `kind` `Controller`, `ControllerPatch`, `Profile`, or `VirtualDevice`.

```javascript
function generate() {
  var sticks = ["LeftStickX", "LeftStickY", "RightStickX", "RightStickY"];
  return [1, 2, 3].map(function (productID) {
    return {
      apiVersion: "openjoystickdriver/v1alpha4",
      kind: "Controller",
      vendorID: 0x1209,
      productID: productID,
      modes: [{ id: "default", protocol: { family: "HIDReportLayout" } }],
      input: { layouts: [{
        report: { length: { atLeast: 8 } },
        buttons: [{ control: "South", bitOffset: 0, bitSize: 1 }],
        axes: sticks.map(function (control, index) {
          return { control: control, bitOffset: 16 + 8 * index, bitSize: 8 };
        })
      }] }
    };
  });
}
```

Constraints that break otherwise-valid JavaScript:

- Sealed runtime: no files, network, processes, timers; `fetch` is a reference error.
- No TypeScript; an annotation is a syntax error.
- Whole numbers → `<integer>`, fractions → `<real>`; `0x1209` is whole.
- Omit keys instead of `null`; `null` anywhere is refused.
- 5 s default limit, global `--timeout SECONDS`; over it `E2010`, script error `E2011` with line.

## Workflow

```text
- [ ] ojd generate family.js                     prints; any failure writes nothing
- [ ] fix the document, key path, and rule each error names
- [ ] ojd generate family.js --output Controllers
- [ ] ojd record validate FILE for each file, then install or package
```

A differing existing file stops the run; ask the user before `--replace`. Mod packages never run `.js`. `1209` is a pid.codes test vendor; shared output uses real VID:PIDs.
