---
name: generating-ojd-documents
description: Writes a JavaScript generator that ojd generate turns into checked OpenJoystickDriver records, patches, profiles, or virtual devices. Use when several controller models differ by a few details.
---

# Generating OJD Documents

Goal: produce many similar OpenJoystickDriver documents from one JavaScript file with `ojd generate`. For a single model, use a record or patch instead.

## Inputs

- The models and how they differ (VID:PIDs, report layout differences).
- An output folder, such as `Controllers`.

## Script Contract

- Define `function generate()` with no argument.
- Return one document or a non-empty list of documents.
- Each document is a plain object with the keys of its property list. `kind` is `Controller`, `ControllerPatch`, `Profile`, or `VirtualDevice`.

```javascript
function generate() {
  var sticks = ["LeftStickX", "LeftStickY", "RightStickX", "RightStickY"];
  return [1, 2, 3].map(function (productID) {
    return {
      apiVersion: "openjoystickdriver/v1alpha3",
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

## Runtime Rules

- The runtime is sealed: no files, network, processes, or timers. `fetch` throws a reference error.
- Write plain JavaScript. A type annotation is a syntax error.
- A whole number becomes `<integer>`; a fraction becomes `<real>`. `0x1209` is a whole number.
- Leave a key out instead of setting `null`. `null` anywhere is refused.
- Time limit: 5 seconds by default; set it with the global `--timeout SECONDS`. Timeout: `E2010`. Script error: `E2011` with message and line.

## Procedure

1. Write `family.js`.
2. Run `ojd generate family.js`. It prints the documents and writes nothing.
3. If it fails, fix the document, key path, and rule it names. One failure writes no file. Repeat step 2.
4. Run `ojd generate family.js --output Controllers`. Each file is named as OJD names its kind, such as `1209-0001.plist`.
5. Run `ojd record validate FILE` for each written file.
6. Install each file with `ojd record install FILE`, or package the folder with `packaging-ojd-mods`.

## Outputs

- The script and one property list per document in the output folder.
- The validation result of each file.

## Stop Conditions

- An existing file with other content stops the command. Ask the user before passing `--replace`.
- Use real VID:PIDs in shared output. `1209` is a pid.codes test vendor.
- Mod packages never run `.js` files; only `ojd generate` runs a script.
