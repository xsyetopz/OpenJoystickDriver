# Generating documents with scripts

Write a JavaScript file that returns controller records, patches, profiles, or virtual devices, and let `ojd generate` check and write them as property list files.

Use a script when you must write many similar documents, for example one record for each product of a controller family. `ojd generate` is the only part of OpenJoystickDriver (OJD) that runs a script. The app, the service, and mod packages read documents only, so a script in a [mod package](Writing-Controller-Mods.md) is never run.

## The generate function

The file must define a function named `generate` that takes no argument. It returns one document, or a list of documents. A document is an object with the same keys as the property list of its kind, and its `kind` key names the kind: `Controller`, `ControllerPatch`, `Profile`, or `VirtualDevice`.

`ojd generate` refuses these results:

- `null`, no value, or a value that is not an object
- an empty list, or a list with an item that is not an object
- a document that holds `null` anywhere. A property list has no null value, so leave the key out.
- a document that its reader refuses. The error names the document, the key path, and the rule.

If one document fails, the command writes none of them.

The script runs in a bare JavaScript context. It has no file, network, process, or timer API, so a call to `fetch` fails with a reference error. The context runs plain JavaScript, so a type annotation is a syntax error. The command reports a syntax error or a thrown exception with its message and its line number.

A whole number that the script returns becomes an `<integer>` in the file, and a fractional number becomes a `<real>`. A hexadecimal literal such as `0x1209` is a whole number.

## The example script

This script returns three controllers that share one input layout. Save it as `pads.js`.

```javascript
function generate() {
  var buttons = ["South", "East", "West", "North", "LeftShoulder", "RightShoulder", "Back", "Start"];
  var sticks = ["LeftStickX", "LeftStickY", "RightStickX", "RightStickY"];
  return [1, 2, 3].map(function (productID) {
    return {
      apiVersion: "openjoystickdriver/v1alpha3",
      kind: "Controller",
      vendorID: 0x1209,
      productID: productID,
      modes: [{ id: "default", protocol: { family: "HIDReportLayout" } }],
      input: {
        layouts: [{
          report: { length: { atLeast: 8 } },
          buttons: buttons.map(function (control, bit) {
            return { control: control, bitOffset: bit, bitSize: 1 };
          }),
          hat: [{ bitOffset: 8, bitSize: 4, encoding: "EightWay" }],
          axes: sticks.map(function (control, index) {
            return { control: control, bitOffset: 16 + 8 * index, bitSize: 8 };
          }),
          leftTrigger: { bitOffset: 48, bitSize: 8 },
          rightTrigger: { bitOffset: 56, bitSize: 8 }
        }]
      }
    };
  });
}
```

`1209` is a pid.codes test vendor ID. Use it only for testing, and use the real VID and PID of your controller in a file you share.

## Run the script

1. Print the documents without a file:

   ```text
   ojd generate pads.js
   ```

2. Write them into a folder:

   ```text
   ojd generate pads.js --output Controllers
   ```

The command writes one file for each document, named as OJD names the same kind of file: `1209-0001.plist` for a controller. It creates the folder when it is missing.

If a file with that name already exists, the command compares it with the new document. An equal file is reported as unchanged. A file with other content stops the command: it names the file and writes nothing. Pass `--replace` to overwrite such a file.

Two documents of one run that need the same file name are an error, and the command writes none of them.

## Set the time limit

The command runs the script in a helper process and ends the process when the script runs too long. The limit is 5 seconds. Use `--timeout SECONDS` to change it. A script that runs past the limit gives error `E2010` and writes no file.

## Further reading

- [Command reference](Command-Reference.md#generate)
- [Controller records](Controller-Records.md)
- [Writing controller mods](Writing-Controller-Mods.md)
