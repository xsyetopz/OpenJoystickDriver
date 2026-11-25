---
name: generating-ojd-documents
description: Writes a JavaScript generator that ojd generate turns into checked OpenJoystickDriver records, patches, profiles, or virtual devices. Use when several controller models differ by a few details.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Generating OJD Documents

`ojd generate` runs one JavaScript file and writes the documents its `generate` function returns. For one controller, a record or patch is simpler.

## The Script

Define `function generate()` with no argument. It returns one document or a list. A document is an object with the keys of its property list, and its `kind` is `Controller`, `ControllerPatch`, `Profile`, or `VirtualDevice`.

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

## Script Limits

- The script runs sealed: no files, network, processes, or timers. `fetch` is a reference error.
- Plain JavaScript only. A type annotation is a syntax error.
- A whole number becomes `<integer>`, a fraction `<real>`. Hex literals such as `0x1209` are whole numbers.
- Leave a key out instead of setting `null`; `null` anywhere is refused.
- The default time limit is 5 seconds; the global `--timeout SECONDS` changes it. Past it: `E2010`. A script error: `E2011` with the message and line.

## Steps

1. Write `family.js`.
2. Print without writing: `ojd generate family.js`. Fix the document, key path, and rule each error names; one failure writes nothing.
3. Write the files: `ojd generate family.js --output Controllers`. Each file is named as OJD names its kind, such as `1209-0001.plist`.
4. A file with other content stops the command. Ask the user before passing `--replace`.
5. Validate and install each file: `ojd record validate FILE`, then `ojd record install FILE`. Or package the folder (`packaging-ojd-mods`).

## Rules

- OJD runs a script only through `ojd generate`. A mod package never runs or copies `.js` files.
- `1209` is a pid.codes test vendor ID. Shared documents use the real VID and PID.
